// Edge Function: arkib-bukti-bayaran
// Dipanggil dari pengurusan.html (kad "Arkib Bukti Bayaran Lama", pemilik sahaja).
// Body: { mod: 'semak' | 'jalankan' }
//   mod='semak'   -> kira berapa fail LAYAK diarkibkan (rekod SELESAI/disahkan,
//                    >2 bulan) + anggaran saiz, TANPA sentuh apa-apa.
//   mod='jalankan'-> muat turun tiap fail drpd Supabase Storage bucket
//                    'bukti-bayaran', POST ke URL webhook (tetapan.arkib_webhook_url,
//                    editable dlm app), padam drpd Storage bila BERJAYA dihantar,
//                    & kemaskini rujukan resit_bukti_url pd rekod DB (permohonan_
//                    bayaran_hutang / transaksi) supaya jelas ia dah diarkibkan.
//
// SEBAB pendekatan webhook (bukan terus API cloud spt Google Drive/Dropbox): OAuth
// pihak ke-3 terlalu kompleks utk edge function tunggal & tak semestinya sepadan
// dgn platform storan awan pilihan pemilik. Webhook (Zapier/Make/n8n/server sendiri)
// ialah corak sejagat yg boleh terima fail (multipart/form-data) & simpan ke
// mana-mana destinasi pemilik pilih sendiri, tanpa edge function ni perlu tahu
// butiran platform tu.

import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const BUCKET = "bukti-bayaran";
const HAD_BILANGAN_SEKALI_JALAN = 100; // hadkan 1 panggilan (elak timeout edge function jika fail terlalu banyak — pemilik boleh tekan sekali lagi utk baki)

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

    const duaBulanLalu = new Date();
    duaBulanLalu.setMonth(duaBulanLalu.getMonth() - 2);
    const potong = duaBulanLalu.toISOString();

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

          const formData = new FormData();
          formData.append("file", fileBlob, namaFail);
          formData.append("sumber", item.sumber);
          formData.append("rekod_id", item.id);
          formData.append("path_asal", item.path);

          const webhookRes = await fetch(webhookUrl, { method: "POST", body: formData });
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
