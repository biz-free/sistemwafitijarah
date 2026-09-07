// Edge Function: arkib-bukti-bayaran
// Dipanggil dari pengurusan.html (kad "Arkib Bukti Bayaran Lama", pemilik sahaja).
// Body: { mod: 'semak' | 'jalankan' }
//   mod='semak'   -> kira berapa fail LAYAK diarkibkan (rekod SELESAI/disahkan,
//                    >1 bulan) + anggaran saiz, TANPA sentuh apa-apa.
//   mod='jalankan'-> jana SIGNED URL sementara (10 minit) bagi tiap fail drpd
//                    Supabase Storage bucket 'bukti-bayaran', POST ke URL webhook
//                    (tetapan.arkib_webhook_url, editable dlm app), padam drpd
//                    Storage bila BERJAYA dihantar, & kemaskini rujukan
//                    resit_bukti_url pd rekod DB (permohonan_bayaran_hutang /
//                    transaksi) supaya jelas ia dah diarkibkan.
//
// SEBAB pendekatan webhook (bukan terus API cloud spt Google Drive/Dropbox): OAuth
// pihak ke-3 terlalu kompleks utk edge function tunggal & tak semestinya sepadan
// dgn platform storan awan pilihan pemilik. Webhook ialah corak sejagat yg boleh
// terima fail & simpan ke mana-mana destinasi pemilik pilih sendiri (Microsoft
// Power Automate + OneDrive, Zapier/Make/n8n + Google Drive/Dropbox, atau server
// sendiri), tanpa edge function ni perlu tahu butiran platform tu.
//
// Format payload: JSON — { nama_fail, file_url, sumber, rekod_id, path_asal }.
//
// PENTING (susulan ujian sebenar pemilik): percubaan PERTAMA hantar kandungan
// fail sbg JSON+base64 (`fail_base64`) — TERNYATA ada 2 isu besar: (1) gelung
// manual String.fromCharCode per-byte utk encode base64 terlajak had CPU Time
// edge function ("CPU Time exceeded", worker crash status 546) utk fail
// beberapa MB (biasa utk gambar resit); (2) walaupun ditukar ke encodeBase64()
// std library (jauh lebih cekap CPU), payload base64 (lebih besar ~33% drpd
// fail asal) MASIH kena tolak oleh webhook Make.com dgn ralat "request entity
// too large" — had saiz webhook Make.com/Power Automate/Zapier biasanya jauh
// lebih kecil drpd saiz gambar resit sebenar (few MB).
//
// PENYELESAIAN: jana SIGNED URL (pautan sementara, sah 10 minit) drpd Supabase
// Storage & hantar PAUTAN tu sahaja dlm payload webhook — BUKAN kandungan fail.
// Servis destinasi (Make.com "HTTP > Get a file", Power Automate "HTTP" action,
// n8n "HTTP Request") muat turun fail terus drpd signed URL tu sendiri, kemudian
// upload ke OneDrive/Google Drive/dll. Edge function ni jadi sangat ringan
// (tiada muat turun/encode fail langsung) — elak SEPENUHNYA isu CPU Time & had
// saiz payload webhook.
//
// Susunan scenario Make.com yg BETUL (3 modul):
//   1. Webhook (Custom webhook) — terima { nama_fail, file_url, sumber, rekod_id, path_asal }
//   2. HTTP > Get a file — URL = {{1.file_url}}
//   3. OneDrive > Upload a file — File Name = {{1.nama_fail}}, Data = {{2.Data}} (output modul 2)

import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const BUCKET = "bukti-bayaran";
const SIGNED_URL_TTL_SAAT = 600; // 10 minit — cukup masa utk webhook/servis destinasi muat turun fail
const HAD_BILANGAN_SEKALI_JALAN = 50; // ringan (tiada muat turun/encode fail dlm edge function ni lagi), boleh proses lebih byk sekali panggilan

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Log masuk diperlukan" }), { status: 401, headers: corsHeaders });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    // Sahkan SIAPA pemanggil (guna JWT sebenar drpd request) sebelum apa-apa tindakan.
    const userClient = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: authHeader } } });
    const { data: userData, error: userErr } = await userClient.auth.getUser();
    if (userErr || !userData?.user) {
      return new Response(JSON.stringify({ error: "Sesi log masuk tidak sah" }), { status: 401, headers: corsHeaders });
    }

    const adminClient = createClient(supabaseUrl, serviceKey);
    const { data: profil } = await adminClient.from("profiles").select("role").eq("id", userData.user.id).single();
    if (profil?.role !== "pemilik") {
      return new Response(JSON.stringify({ error: "Hanya pemilik boleh guna ciri arkib ini" }), { status: 403, headers: corsHeaders });
    }

    const { mod } = await req.json();

    const sebulanLalu = new Date();
    sebulanLalu.setMonth(sebulanLalu.getMonth() - 1);
    const potong = sebulanLalu.toISOString();

    const { data: hutangList } = await adminClient
      .from("permohonan_bayaran_hutang")
      .select("id, resit_bukti_url, created_at")
      .eq("status", "disahkan")
      .not("resit_bukti_url", "is", null)
      .not("resit_bukti_url", "ilike", "ARKIB:%")
      .lt("created_at", potong);

    const { data: trxList } = await adminClient
      .from("transaksi")
      .select("id, resit_bukti_url, tarikh_masa")
      .eq("status", "selesai")
      .not("resit_bukti_url", "is", null)
      .not("resit_bukti_url", "ilike", "ARKIB:%")
      .lt("tarikh_masa", potong);

    const senarai = [
      ...(hutangList || []).map((r: any) => ({ sumber: "permohonan_bayaran_hutang", id: r.id, path: r.resit_bukti_url })),
      ...(trxList || []).map((r: any) => ({ sumber: "transaksi", id: r.id, path: r.resit_bukti_url })),
    ].filter(x => x.path); // buang null/kosong keluar keputusan carian di atas jika ada

    if (mod === "semak") {
      const paths = senarai.map(x => x.path);
      let anggaranSaiz = 0;
      if (paths.length) {
        const { data: saizData } = await adminClient.rpc("get_saiz_fail_storan", { p_bucket: BUCKET, p_paths: paths });
        anggaranSaiz = Number(saizData) || 0;
      }
      return new Response(
        JSON.stringify({ bilangan: senarai.length, anggaran_saiz_bytes: anggaranSaiz }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    if (mod === "jalankan") {
      const { data: tetapan } = await adminClient.from("tetapan").select("arkib_webhook_url").eq("id", 1).single();
      const webhookUrl = tetapan?.arkib_webhook_url;
      if (!webhookUrl) {
        return new Response(JSON.stringify({ error: "URL webhook arkib belum ditetapkan — sila isi & simpan dahulu" }), { status: 400, headers: corsHeaders });
      }

      const senaraiJalan = senarai.slice(0, HAD_BILANGAN_SEKALI_JALAN);

      // Saiz sebenar tiap fail (utk laporan "saiz dijimatkan") — WAJIB dikira
      // SEBELUM apa-apa dipadam (lookup lepas padam pulangkan 0, rekod storan dah
      // tiada). get_saiz_fail_storan() pulangkan JUMLAH agregat sahaja, jadi
      // panggil sekali per-path (jumlah kecil bila had 50/panggilan, bukan isu).
      const petaSaiz: Record<string, number> = {};
      for (const item of senaraiJalan) {
        const { data: saizSatu } = await adminClient.rpc("get_saiz_fail_storan", { p_bucket: BUCKET, p_paths: [item.path] });
        petaSaiz[item.path] = Number(saizSatu) || 0;
      }

      let berjaya = 0, gagal = 0, saizDijimatkan = 0;
      const ralatSenarai: string[] = [];

      for (const item of senaraiJalan) {
        try {
          const { data: signedData, error: signErr } = await adminClient.storage
            .from(BUCKET)
            .createSignedUrl(item.path, SIGNED_URL_TTL_SAAT);
          if (signErr || !signedData?.signedUrl) {
            gagal++;
            const m = `${item.path}: gagal jana pautan sementara — ${signErr?.message || 'ralat tidak diketahui'}`;
            console.error(m);
            ralatSenarai.push(m);
            continue;
          }

          const namaFail = item.path.split("/").pop() || item.path;

          const webhookRes = await fetch(webhookUrl, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
              nama_fail: namaFail,
              file_url: signedData.signedUrl,
              sumber: item.sumber,
              rekod_id: item.id,
              path_asal: item.path,
            }),
          });
          if (!webhookRes.ok) {
            gagal++;
            let badanRalat = '';
            try { badanRalat = (await webhookRes.text()).slice(0, 300); } catch { /* biar kosong jika gagal baca */ }
            const m = `${item.path}: webhook pulangkan status ${webhookRes.status}${badanRalat ? ` — ${badanRalat}` : ''}`;
            console.error(m);
            ralatSenarai.push(m);
            continue;
          }

          let urlBaharu: string | null = null;
          try {
            const webhookJson = await webhookRes.json();
            urlBaharu = webhookJson?.url || webhookJson?.link || null;
          } catch { /* webhook tak pulangkan JSON — teruskan tanpa url baharu, bukan ralat */ }

          const { error: rmErr } = await adminClient.storage.from(BUCKET).remove([item.path]);
          if (rmErr) {
            gagal++;
            const m = `${item.path}: DAH dihantar ke webhook tapi GAGAL dipadam drpd Supabase (${rmErr.message}) — sila padam manual`;
            console.error(m);
            ralatSenarai.push(m);
            continue;
          }

          const nilaiBaharu = urlBaharu ? `ARKIB:${urlBaharu}` : `ARKIB:dipindah-${new Date().toISOString().slice(0, 10)}`;
          await adminClient.from(item.sumber).update({ resit_bukti_url: nilaiBaharu }).eq("id", item.id);

          berjaya++;
          saizDijimatkan += petaSaiz[item.path] || 0;
        } catch (e) {
          gagal++;
          const m = `${item.path}: ${String((e as Error)?.message || e)}`;
          console.error(m);
          ralatSenarai.push(m);
        }
      }

      return new Response(
        JSON.stringify({ berjaya, gagal, saiz_dijimatkan_bytes: saizDijimatkan, ralat: ralatSenarai.slice(0, 20), baki_belum_diproses: Math.max(0, senarai.length - senaraiJalan.length) }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    return new Response(JSON.stringify({ error: "Param 'mod' tidak sah — guna 'semak' atau 'jalankan'" }), { status: 400, headers: corsHeaders });
  } catch (e) {
    return new Response(JSON.stringify({ error: String((e as Error)?.message || e) }), { status: 500, headers: corsHeaders });
  }
});
