// Edge Function: arkib-bukti-bayaran
// Dipanggil dari pengurusan.html (kad "Arkib Bukti Bayaran Lama", pemilik sahaja).
// Body: { mod: 'semak' | 'jalankan' | 'sahkan' | 'batal' }
//   mod='semak'   -> kira berapa fail LAYAK diarkibkan (rekod SELESAI/disahkan,
//                    >1 bulan) + anggaran saiz + berapa MENUNGGU pengesahan,
//                    TANPA sentuh apa-apa.
//   mod='jalankan'-> jana SIGNED URL sementara (10 minit) bagi tiap fail drpd
//                    Supabase Storage bucket 'bukti-bayaran', POST ke URL webhook
//                    (tetapan.arkib_webhook_url, editable dlm app). TIDAK padam
//                    fail asal serta-merta — cuma tanda rekod sbg
//                    "ARKIB_MENUNGGU:<path_asal>" (menunggu pengesahan pemilik).
//   mod='sahkan'  -> utk SEMUA rekod ARKIB_MENUNGGU: pemilik dah semak fail betul2
//                    sampai OneDrive/storan luaran -> BARU padam fail asal drpd
//                    Supabase Storage & tukar tanda ke "ARKIB:selesai-<tarikh>".
//   mod='batal'   -> utk SEMUA rekod ARKIB_MENUNGGU: pulangkan balik resit_bukti_url
//                    kpd path asal (batal proses, fail asal x disentuh, blh cuba lagi).
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
// PENTING (susulan ujian sebenar pemilik — 2 isu besar ditemui berturutan):
// (1) percubaan PERTAMA hantar kandungan fail sbg JSON+base64 (`fail_base64`) —
//     gelung manual String.fromCharCode per-byte terlajak had CPU Time edge
//     function ("CPU Time exceeded", status 546) utk fail beberapa MB; ditukar
//     ke encodeBase64() std library — tapi payload base64 (lebih besar ~33%)
//     MASIH kena tolak webhook Make.com dgn "request entity too large".
// (2) DITUKAR ke jana SIGNED URL (pautan sementara 10 minit) & hantar PAUTAN
//     sahaja dlm payload webhook (bukan kandungan fail) — servis destinasi
//     (Make.com "HTTP > Download a file", dll) muat turun fail terus drpd
//     signed URL, upload ke OneDrive/dll. TAPI reka bentuk ASAL memadam fail
//     drpd Supabase Storage sebaik SAHAJA webhook pulangkan HTTP 200 — INI SILAP
//     BESAR: kebanyakan platform webhook (Make.com, Zapier, dll) auto-balas 200
//     "Accepted" SERTA-MERTA bila permintaan diterima, BUKAN selepas keseluruhan
//     aliran kerja (termasuk upload OneDrive) selesai dijalankan. Akibatnya —
//     terbukti dlm ujian sebenar pemilik — 20 fail resit PADAM drpd Supabase
//     SEBELUM sempat sampai OneDrive (aliran Make.com blm siap diuji sepenuhnya
//     ketika tu), fail-fail tu HILANG KEKAL (Supabase Storage free tier tiada
//     recycle bin/undo padam).
//
// PENYELESAIAN (reka bentuk semasa — 2 LANGKAH, ada jurang pengesahan manusia):
//   Langkah 1 ("jalankan"): hantar signed URL ke webhook, tanda rekod
//   "ARKIB_MENUNGGU:<path>" — fail asal KEKAL selamat di Supabase.
//   Langkah 2 ("sahkan", butang berasingan "✅ Sahkan & Padam Fail Asal"):
//   HANYA lepas pemilik SENDIRI semak & sahkan fail betul2 sampai destinasi
//   (cth buka folder OneDrive, tengok fail ada) — barulah fail asal dipadam.
//   Ada juga "batal" utk urungkan balik jika sesuatu tak kena sblm disahkan.
//
// Susunan scenario Make.com yg BETUL (3 modul):
//   1. Webhook (Custom webhook) — terima { nama_fail, file_url, sumber, rekod_id, path_asal }
//   2. HTTP > Download a file — URL = {{1.file_url}}
//   3. OneDrive > Upload a file — File Name = {{1.nama_fail}}, Data = {{2.Data}} (output modul 2)

import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const BUCKET = "bukti-bayaran";
const SIGNED_URL_TTL_SAAT = 600; // 10 minit — cukup masa utk webhook/servis destinasi muat turun fail
const HAD_BILANGAN_SEKALI_JALAN = 50; // ringan (tiada muat turun/encode fail dlm edge function ni lagi), boleh proses lebih byk sekali panggilan
const PREFIX_MENUNGGU = "ARKIB_MENUNGGU:";
const PREFIX_SELESAI = "ARKIB:";

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

    // Ambil senarai rekod MENUNGGU pengesahan (ARKIB_MENUNGGU:<path>) drpd kedua-dua jadual.
    async function ambilSenaraiMenunggu() {
      const { data: hutangM } = await adminClient
        .from("permohonan_bayaran_hutang").select("id, resit_bukti_url").ilike("resit_bukti_url", `${PREFIX_MENUNGGU}%`);
      const { data: trxM } = await adminClient
        .from("transaksi").select("id, resit_bukti_url").ilike("resit_bukti_url", `${PREFIX_MENUNGGU}%`);
      return [
        ...(hutangM || []).map((r: any) => ({ sumber: "permohonan_bayaran_hutang", id: r.id, path: String(r.resit_bukti_url).slice(PREFIX_MENUNGGU.length) })),
        ...(trxM || []).map((r: any) => ({ sumber: "transaksi", id: r.id, path: String(r.resit_bukti_url).slice(PREFIX_MENUNGGU.length) })),
      ];
    }

    if (mod === "semak") {
      const { data: hutangList } = await adminClient
        .from("permohonan_bayaran_hutang").select("resit_bukti_url").eq("status", "disahkan")
        .not("resit_bukti_url", "is", null).not("resit_bukti_url", "ilike", `${PREFIX_SELESAI}%`).not("resit_bukti_url", "ilike", `${PREFIX_MENUNGGU}%`).lt("created_at", potong);
      const { data: trxList } = await adminClient
        .from("transaksi").select("resit_bukti_url").eq("status", "selesai")
        .not("resit_bukti_url", "is", null).not("resit_bukti_url", "ilike", `${PREFIX_SELESAI}%`).not("resit_bukti_url", "ilike", `${PREFIX_MENUNGGU}%`).lt("tarikh_masa", potong);
      const paths = [...(hutangList || []), ...(trxList || [])].map((r: any) => r.resit_bukti_url).filter(Boolean);
      let anggaranSaiz = 0;
      if (paths.length) {
        const { data: saizData } = await adminClient.rpc("get_saiz_fail_storan", { p_bucket: BUCKET, p_paths: paths });
        anggaranSaiz = Number(saizData) || 0;
      }
      const senaraiMenunggu = await ambilSenaraiMenunggu();
      return new Response(
        JSON.stringify({ bilangan: paths.length, anggaran_saiz_bytes: anggaranSaiz, menunggu_pengesahan: senaraiMenunggu.length }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    if (mod === "jalankan") {
      const { data: tetapan } = await adminClient.from("tetapan").select("arkib_webhook_url").eq("id", 1).single();
      const webhookUrl = tetapan?.arkib_webhook_url;
      if (!webhookUrl) {
        return new Response(JSON.stringify({ error: "URL webhook arkib belum ditetapkan — sila isi & simpan dahulu" }), { status: 400, headers: corsHeaders });
      }

      const { data: hutangList } = await adminClient
        .from("permohonan_bayaran_hutang").select("id, resit_bukti_url, created_at").eq("status", "disahkan")
        .not("resit_bukti_url", "is", null).not("resit_bukti_url", "ilike", `${PREFIX_SELESAI}%`).not("resit_bukti_url", "ilike", `${PREFIX_MENUNGGU}%`).lt("created_at", potong);
      const { data: trxList } = await adminClient
        .from("transaksi").select("id, resit_bukti_url, tarikh_masa").eq("status", "selesai")
        .not("resit_bukti_url", "is", null).not("resit_bukti_url", "ilike", `${PREFIX_SELESAI}%`).not("resit_bukti_url", "ilike", `${PREFIX_MENUNGGU}%`).lt("tarikh_masa", potong);

      const senarai = [
        ...(hutangList || []).map((r: any) => ({ sumber: "permohonan_bayaran_hutang", id: r.id, path: r.resit_bukti_url })),
        ...(trxList || []).map((r: any) => ({ sumber: "transaksi", id: r.id, path: r.resit_bukti_url })),
      ].filter(x => x.path);

      const senaraiJalan = senarai.slice(0, HAD_BILANGAN_SEKALI_JALAN);

      let berjaya = 0, gagal = 0;
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

          // PENTING: TIDAK padam fail asal di sini. Webhook 200 OK cuma bermaksud
          // "permintaan diterima" (kebanyakan platform spt Make.com/Zapier balas
          // serta-merta), BUKAN "fail dah sampai OneDrive/destinasi selesai".
          // Fail asal hanya dipadam selepas pemilik sendiri sahkan (mod='sahkan').
          await adminClient.from(item.sumber).update({ resit_bukti_url: `${PREFIX_MENUNGGU}${item.path}` }).eq("id", item.id);
          berjaya++;
        } catch (e) {
          gagal++;
          const m = `${item.path}: ${String((e as Error)?.message || e)}`;
          console.error(m);
          ralatSenarai.push(m);
        }
      }

      return new Response(
        JSON.stringify({ berjaya, gagal, ralat: ralatSenarai.slice(0, 20), baki_belum_diproses: Math.max(0, senarai.length - senaraiJalan.length) }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    if (mod === "sahkan") {
      const senaraiMenunggu = await ambilSenaraiMenunggu();
      if (!senaraiMenunggu.length) {
        return new Response(JSON.stringify({ berjaya: 0, gagal: 0, saiz_dijimatkan_bytes: 0, ralat: [] }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
      }
      // Kira saiz SEBELUM padam (lookup lepas padam pulangkan 0).
      const petaSaiz: Record<string, number> = {};
      for (const item of senaraiMenunggu) {
        const { data: saizSatu } = await adminClient.rpc("get_saiz_fail_storan", { p_bucket: BUCKET, p_paths: [item.path] });
        petaSaiz[item.path] = Number(saizSatu) || 0;
      }

      let berjaya = 0, gagal = 0, saizDijimatkan = 0;
      const ralatSenarai: string[] = [];
      for (const item of senaraiMenunggu) {
        try {
          const { error: rmErr } = await adminClient.storage.from(BUCKET).remove([item.path]);
          if (rmErr) {
            gagal++;
            const m = `${item.path}: gagal dipadam drpd Supabase (${rmErr.message})`;
            console.error(m);
            ralatSenarai.push(m);
            continue;
          }
          await adminClient.from(item.sumber).update({ resit_bukti_url: `${PREFIX_SELESAI}selesai-${new Date().toISOString().slice(0, 10)}` }).eq("id", item.id);
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
        JSON.stringify({ berjaya, gagal, saiz_dijimatkan_bytes: saizDijimatkan, ralat: ralatSenarai.slice(0, 20) }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    if (mod === "batal") {
      const senaraiMenunggu = await ambilSenaraiMenunggu();
      let berjaya = 0;
      for (const item of senaraiMenunggu) {
        await adminClient.from(item.sumber).update({ resit_bukti_url: item.path }).eq("id", item.id);
        berjaya++;
      }
      return new Response(JSON.stringify({ berjaya }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    return new Response(JSON.stringify({ error: "Param 'mod' tidak sah — guna 'semak', 'jalankan', 'sahkan' atau 'batal'" }), { status: 400, headers: corsHeaders });
  } catch (e) {
    return new Response(JSON.stringify({ error: String((e as Error)?.message || e) }), { status: 500, headers: corsHeaders });
  }
});
