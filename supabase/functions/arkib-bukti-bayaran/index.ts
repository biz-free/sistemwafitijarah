// Edge Function: arkib-bukti-bayaran
// Dipanggil dari pengurusan.html (kad "Arkib Bukti Bayaran Lama", pemilik sahaja).
// Body: { mod: 'semak' | 'jalankan' }
//   mod='semak'   -> kira berapa fail LAYAK diarkibkan (rekod SELESAI/disahkan,
//                    >1 bulan) + anggaran saiz, TANPA sentuh apa-apa.
//   mod='jalankan'-> muat turun tiap fail drpd Supabase Storage bucket
//                    'bukti-bayaran', POST ke URL webhook (tetapan.arkib_webhook_url,
//                    editable dlm app), padam drpd Storage bila BERJAYA dihantar,
//                    & kemaskini rujukan resit_bukti_url pd rekod DB (permohonan_
//                    bayaran_hutang / transaksi) supaya jelas ia dah diarkibkan.
//
// SEBAB pendekatan webhook (bukan terus API cloud spt Google Drive/Dropbox): OAuth
// pihak ke-3 terlalu kompleks utk edge function tunggal & tak semestinya sepadan
// dgn platform storan awan pilihan pemilik. Webhook ialah corak sejagat yg boleh
// terima fail & simpan ke mana-mana destinasi pemilik pilih sendiri (Microsoft
// Power Automate + OneDrive, Zapier/Make/n8n + Google Drive/Dropbox, atau server
// sendiri), tanpa edge function ni perlu tahu butiran platform tu.
//
// Format payload: JSON (bukan multipart/form-data) — { nama_fail, content_type,
// fail_base64, sumber, rekod_id, path_asal }. Sengaja JSON+base64 supaya senang
// diproses Power Automate ("When a HTTP request is received" + "OneDrive - Create
// file", guna base64ToBinary(triggerBody()?['fail_base64']) pada kandungan fail)
// tanpa perlu urai multipart yang lebih rumit di Power Automate.

import { createClient } from "npm:@supabase/supabase-js@2";
import { encodeBase64 } from "jsr:@std/encoding@1/base64";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const BUCKET = "bukti-bayaran";
const HAD_BILANGAN_SEKALI_JALAN = 20; // hadkan 1 panggilan (elak had CPU Time edge function jika byk fail besar — pemilik boleh tekan sekali lagi utk baki, lihat baki_belum_diproses)

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
      let berjaya = 0, gagal = 0, saizDijimatkan = 0;
      const ralatSenarai: string[] = [];

      for (const item of senaraiJalan) {
        try {
          const { data: fileBlob, error: dlErr } = await adminClient.storage.from(BUCKET).download(item.path);
          if (dlErr || !fileBlob) { gagal++; ralatSenarai.push(`${item.path}: gagal muat turun drpd storan`); continue; }

          const saizFail = fileBlob.size;
          const namaFail = item.path.split("/").pop() || item.path;

          // JSON + base64 (bukan multipart/form-data) — sengaja dipilih supaya senang
          // diproses oleh Microsoft Power Automate ("When a HTTP request is received"
          // + "OneDrive - Create file", guna expression base64ToBinary() pada medan
          // fail_base64) tanpa perlu urai multipart yang lebih rumit. Servis lain
          // (Zapier/Make/n8n) turut boleh terima JSON macam ni dgn mudah.
          //
          // PENTING: guna encodeBase64() std library (bukan gelung String.fromCharCode
          // per-byte manual) — gelung manual utk fail beberapa MB (biasa utk gambar
          // resit/bukti transfer) terlajak had CPU Time edge function ("CPU Time
          // exceeded", worker crash status 546) — ditemui semasa ujian sebenar pemilik.
          const fail_base64 = encodeBase64(await fileBlob.arrayBuffer());

          const webhookRes = await fetch(webhookUrl, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
              nama_fail: namaFail,
              content_type: fileBlob.type || "application/octet-stream",
              fail_base64,
              sumber: item.sumber,
              rekod_id: item.id,
              path_asal: item.path,
            }),
          });
          if (!webhookRes.ok) { gagal++; ralatSenarai.push(`${item.path}: webhook pulangkan status ${webhookRes.status}`); continue; }

          let urlBaharu: string | null = null;
          try {
            const webhookJson = await webhookRes.json();
            urlBaharu = webhookJson?.url || webhookJson?.link || null;
          } catch { /* webhook tak pulangkan JSON — teruskan tanpa url baharu, bukan ralat */ }

          const { error: rmErr } = await adminClient.storage.from(BUCKET).remove([item.path]);
          if (rmErr) {
            gagal++;
            ralatSenarai.push(`${item.path}: DAH dihantar ke webhook tapi GAGAL dipadam drpd Supabase — sila padam manual`);
            continue;
          }

          const nilaiBaharu = urlBaharu ? `ARKIB:${urlBaharu}` : `ARKIB:dipindah-${new Date().toISOString().slice(0, 10)}`;
          await adminClient.from(item.sumber).update({ resit_bukti_url: nilaiBaharu }).eq("id", item.id);

          berjaya++;
          saizDijimatkan += saizFail;
        } catch (e) {
          gagal++;
          ralatSenarai.push(`${item.path}: ${String((e as Error)?.message || e)}`);
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
