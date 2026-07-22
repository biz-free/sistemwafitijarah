// Edge Function: rujukan-ganjaran-cron
// Dijadualkan SETIAP 15 MINIT oleh pg_cron (juga boleh dipanggil terus oleh
// pemilik dari pengurusan.html untuk "Jana Sekarang") — cari pesanan yang
// DISAHKAN bayar dan ada kod_rujukan, tapi BELUM diproses (tiada rekod dalam
// rujukan_ganjaran), jana baucar ganjaran untuk PERUJUK (nombor telefon yang
// dikongsi sebagai kod rujukan), dan hantar emel pemberitahuan jika perujuk
// ada alamat emel berdaftar.
//
// Sengaja diproses SELEPAS bayaran disahkan (bukan serta-merta semasa
// checkout) — elak ganjaran diberi untuk pesanan yang akhirnya tak jadi
// dibayar/dibatalkan.
//
// Dua cara pengesahan (sama seperti winback-auto-cron):
// 1. pg_cron — header x-cron-secret dipadankan dengan secret CRON_SECRET.
// 2. Pemilik log masuk dari pengurusan.html — untuk butang "Jana Sekarang".
//
// Setup wajib: guna semula secret RESEND_API_KEY & CRON_SECRET sedia ada —
// tiada secret baharu diperlukan.

import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
};

const FROM_EMAIL = "Wafi Tijarah Trading <no-reply@wafitijarahtrading.com>";

function esc(s: unknown): string {
  return String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c] as string));
}

function janaKodGanjaran(): string {
  const aksara = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // elak 0/O/1/I yang mengelirukan
  let kod = "RUJUK";
  for (let i = 0; i < 6; i++) kod += aksara[Math.floor(Math.random() * aksara.length)];
  return kod;
}

async function pengesahanSah(req: Request): Promise<boolean> {
  const cronSecret = Deno.env.get("CRON_SECRET");
  if (cronSecret && req.headers.get("x-cron-secret") === cronSecret) return true;

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return false;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const callerClient = createClient(Deno.env.get("SUPABASE_URL")!, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user } } = await callerClient.auth.getUser();
  if (!user) return false;
  const { data: profile } = await callerClient.from("profiles").select("role").eq("id", user.id).single();
  return profile?.role === "pemilik";
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    if (!(await pengesahanSah(req))) {
      return new Response(JSON.stringify({ error: "Tidak dibenarkan" }), { status: 401, headers: corsHeaders });
    }

    const adminClient = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const resendKey = Deno.env.get("RESEND_API_KEY");

    const { data: tetapan } = await adminClient
      .from("tetapan")
      .select("rujukan_ganjaran_rm, rujukan_luput_hari")
      .eq("id", 1)
      .single();
    const ganjaranRm = tetapan?.rujukan_ganjaran_rm ?? 10;
    const luputHari = tetapan?.rujukan_luput_hari ?? 90;

    // Pesanan disahkan bayar + ada kod_rujukan.
    const { data: pesananList, error: qErr } = await adminClient
      .from("pesanan_edagang")
      .select("id, pelanggan_telefon, kod_rujukan, status_bayaran")
      .eq("status_bayaran", "disahkan")
      .not("kod_rujukan", "is", null);
    if (qErr) return new Response(JSON.stringify({ error: qErr.message }), { status: 500, headers: corsHeaders });

    // Yang dah diproses (ada dalam rujukan_ganjaran) — langkau.
    const { data: sudahProses } = await adminClient.from("rujukan_ganjaran").select("pesanan_id");
    const sudahProsesSet = new Set((sudahProses || []).map((r) => r.pesanan_id));

    const calon = (pesananList || []).filter((o) => o.kod_rujukan && !sudahProsesSet.has(o.id));

    let dijana = 0, emelDihantar = 0;
    for (const pesanan of calon) {
      const telefonPerujuk = pesanan.kod_rujukan!;

      // Cari nama & emel terkini perujuk daripada pesanan lepas mereka.
      const { data: dataPerujuk } = await adminClient
        .from("pesanan_edagang")
        .select("pelanggan_nama, pelanggan_email, created_at")
        .eq("pelanggan_telefon", telefonPerujuk)
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();

      const kodGanjaran = janaKodGanjaran();
      const tarikhLuput = new Date(Date.now() + luputHari * 24 * 60 * 60 * 1000).toISOString().slice(0, 10);

      const { error: baucarErr } = await adminClient.from("baucar").insert({
        kod: kodGanjaran, jenis_diskaun: "tetap", nilai_diskaun: ganjaranRm,
        had_guna: 1, aktif: true, tarikh_luput: tarikhLuput,
      });
      if (baucarErr) { console.error(`[rujukan ${pesanan.id}] Gagal cipta baucar:`, baucarErr.message); continue; }

      const { error: logErr } = await adminClient.from("rujukan_ganjaran").insert({
        pesanan_id: pesanan.id, telefon_perujuk: telefonPerujuk, telefon_kawan: pesanan.pelanggan_telefon,
        kod_ganjaran: kodGanjaran, nilai_ganjaran: ganjaranRm,
      });
      if (logErr) { console.error(`[rujukan ${pesanan.id}] Gagal log ganjaran:`, logErr.message); continue; }
      dijana++;

      if (resendKey && dataPerujuk?.pelanggan_email) {
        const html = `
          <div style="font-family:Arial,sans-serif;color:#16241D;max-width:480px;margin:0 auto">
            <h2 style="color:#0B3D2E">Wafi Tijarah Trading</h2>
            <p>Assalamualaikum ${esc(dataPerujuk.pelanggan_nama || "")},</p>
            <p>Terima kasih rujuk kawan anda kepada kami! 🎉 Kawan anda baru sahaja membuat pesanan pertama guna kod rujukan anda.</p>
            <p style="background:#F0FFF4;border:1px solid #1D7A4A;border-radius:8px;padding:10px 14px;text-align:center"><b>Ganjaran anda: RM${ganjaranRm.toFixed(2)}</b><br>Kod: <span style="font-size:16px;letter-spacing:1px">${esc(kodGanjaran)}</span></p>
            <p>Guna kod ini semasa checkout untuk pesanan seterusnya (sah sehingga ${tarikhLuput}).</p>
            <p><a href="https://www.wafitijarahtrading.com/" style="background:#0B3D2E;color:#fff;padding:10px 18px;border-radius:8px;text-decoration:none;display:inline-block">🛍️ Layari Kedai Online</a></p>
          </div>`;
        const resendRes = await fetch("https://api.resend.com/emails", {
          method: "POST",
          headers: { "Authorization": `Bearer ${resendKey}`, "Content-Type": "application/json" },
          body: JSON.stringify({ from: FROM_EMAIL, to: [dataPerujuk.pelanggan_email], subject: "Ganjaran rujukan anda! 🎉 — Wafi Tijarah Trading", html }),
        });
        if (resendRes.ok) {
          await adminClient.from("rujukan_ganjaran").update({ emel_dihantar: true }).eq("pesanan_id", pesanan.id);
          emelDihantar++;
        } else {
          console.error(`[rujukan ${pesanan.id}] Resend gagal:`, resendRes.status, await resendRes.text());
        }
      }
    }

    return new Response(JSON.stringify({ dijana, emelDihantar, jumlahCalon: calon.length }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error("rujukan-ganjaran-cron error:", e);
    return new Response(JSON.stringify({ error: String(e?.message || e) }), { status: 500, headers: corsHeaders });
  }
});
