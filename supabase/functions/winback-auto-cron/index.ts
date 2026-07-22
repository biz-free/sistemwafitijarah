// Edge Function: winback-auto-cron
// Dijadualkan MINGGUAN oleh pg_cron (juga boleh dipanggil terus oleh pemilik
// dari pengurusan.html untuk "Jana Sekarang") — cari pelanggan yang pernah
// beli (pesanan_edagang, status_bayaran='disahkan') tapi sudah lama tidak
// beli lagi (default 60 hari), hantar emel "kami rindu awak" dengan kod
// voucher pilihan pemilik (jika ditetapkan). Cooldown (default 90 hari)
// elak emel sama dihantar berulang-ulang kepada pelanggan yang sama.
//
// Dua cara pengesahan dibenarkan:
// 1. pg_cron — header x-cron-secret dipadankan dengan secret CRON_SECRET
//    (sama seperti susulan-auto-cron).
// 2. Pemilik log masuk dari pengurusan.html (token pemanggil disahkan +
//    jadual profiles.role === 'pemilik') — untuk butang "Jana Sekarang".
//
// Setup wajib: guna semula secret RESEND_API_KEY & CRON_SECRET sedia ada
// (dari susulan-auto-cron) — tiada secret baharu diperlukan.

import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
};

const FROM_EMAIL = "Wafi Tijarah Trading <no-reply@wafitijarahtrading.com>";
const HAD_MAKSIMUM_SEKALI_JALAN = 300; // had keselamatan — elak letupan emel pertama kali diaktifkan

function esc(s: unknown): string {
  return String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c] as string));
}

async function pengesahanSah(req: Request, adminClient: ReturnType<typeof createClient>): Promise<boolean> {
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
    const adminClient = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

    if (!(await pengesahanSah(req, adminClient))) {
      return new Response(JSON.stringify({ error: "Tidak dibenarkan" }), { status: 401, headers: corsHeaders });
    }

    const { data: tetapan } = await adminClient
      .from("tetapan")
      .select("winback_aktif, winback_hari_tidak_aktif, winback_cooldown_hari, winback_kod_voucher")
      .eq("id", 1)
      .single();

    if (!tetapan?.winback_aktif) {
      return new Response(JSON.stringify({ mesej: "Kempen win-back tidak aktif — tiada emel dihantar", dihantar: 0 }), {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const resendKey = Deno.env.get("RESEND_API_KEY");
    if (!resendKey) {
      return new Response(JSON.stringify({ error: "RESEND_API_KEY belum ditetapkan sebagai secret" }), { status: 500, headers: corsHeaders });
    }

    const hariTidakAktif = tetapan.winback_hari_tidak_aktif ?? 60;
    const cooldownHari = tetapan.winback_cooldown_hari ?? 90;
    const kodVoucher = (tetapan.winback_kod_voucher || "").trim().toUpperCase() || null;

    // Sahkan kod voucher (jika ditetapkan) masih wujud & aktif — elak sebut kod yang dah luput/dipadam.
    let voucherSahDisebut = false;
    if (kodVoucher) {
      const { data: baucar } = await adminClient.from("baucar").select("kod, aktif, tarikh_luput").eq("kod", kodVoucher).maybeSingle();
      const hariIni = new Date().toISOString().slice(0, 10);
      voucherSahDisebut = !!baucar?.aktif && (!baucar.tarikh_luput || baucar.tarikh_luput >= hariIni);
    }

    // Kumpul semua pesanan yang DISAHKAN bayar — asas untuk kenal pasti pelanggan sebenar & tarikh belian terakhir.
    const { data: pesananList, error: qErr } = await adminClient
      .from("pesanan_edagang")
      .select("pelanggan_nama, pelanggan_telefon, pelanggan_email, created_at")
      .eq("status_bayaran", "disahkan")
      .not("pelanggan_email", "is", null);
    if (qErr) return new Response(JSON.stringify({ error: qErr.message }), { status: 500, headers: corsHeaders });

    const ikutTelefon = new Map<string, { nama: string; email: string; terakhir: string }>();
    for (const o of pesananList || []) {
      const sedia = ikutTelefon.get(o.pelanggan_telefon);
      if (!sedia || o.created_at > sedia.terakhir) {
        ikutTelefon.set(o.pelanggan_telefon, { nama: o.pelanggan_nama, email: o.pelanggan_email, terakhir: o.created_at });
      }
    }

    const sempadanTidakAktif = Date.now() - hariTidakAktif * 24 * 60 * 60 * 1000;
    const calon = [...ikutTelefon.entries()]
      .filter(([, c]) => new Date(c.terakhir).getTime() <= sempadanTidakAktif)
      .sort((a, b) => new Date(a[1].terakhir).getTime() - new Date(b[1].terakhir).getTime()); // paling lama tak aktif dahulu

    let dihantar = 0, dilangkauCooldown = 0, dilangkauHad = 0;
    const sempadanCooldown = new Date(Date.now() - cooldownHari * 24 * 60 * 60 * 1000).toISOString();

    for (const [telefon, c] of calon) {
      if (dihantar >= HAD_MAKSIMUM_SEKALI_JALAN) { dilangkauHad++; continue; }

      const { data: logSedia } = await adminClient
        .from("winback_log")
        .select("dihantar_pada")
        .eq("telefon", telefon)
        .order("dihantar_pada", { ascending: false })
        .limit(1)
        .maybeSingle();
      if (logSedia && logSedia.dihantar_pada > sempadanCooldown) { dilangkauCooldown++; continue; }

      const hariBerlalu = Math.floor((Date.now() - new Date(c.terakhir).getTime()) / (24 * 60 * 60 * 1000));
      const voucherHtml = voucherSahDisebut
        ? `<p style="background:#F0FFF4;border:1px solid #1D7A4A;border-radius:8px;padding:10px 14px;text-align:center"><b>Guna kod <span style="font-size:16px;letter-spacing:1px">${esc(kodVoucher)}</span> untuk diskaun istimewa!</b></p>`
        : "";

      const html = `
        <div style="font-family:Arial,sans-serif;color:#16241D;max-width:480px;margin:0 auto">
          <h2 style="color:#0B3D2E">Wafi Tijarah Trading</h2>
          <p>Assalamualaikum ${esc(c.nama)},</p>
          <p>Sudah ${hariBerlalu} hari sejak pembelian terakhir anda bersama kami — kami rindu! 🌙</p>
          <p>Produk halal berkualiti kami sentiasa sedia menanti — jom singgah lagi.</p>
          ${voucherHtml}
          <p><a href="https://www.wafitijarahtrading.com/" style="background:#0B3D2E;color:#fff;padding:10px 18px;border-radius:8px;text-decoration:none;display:inline-block">🛍️ Layari Kedai Online</a></p>
          <p style="font-size:12px;color:#5C7A6C">Jika tidak mahu terima emel seumpama ini lagi, sila hubungi kami di wafitijarahtrading@gmail.com.</p>
        </div>`;

      const resendRes = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: { "Authorization": `Bearer ${resendKey}`, "Content-Type": "application/json" },
        body: JSON.stringify({ from: FROM_EMAIL, to: [c.email], subject: "Kami rindu awak! 🌙 — Wafi Tijarah Trading", html }),
      });
      const resendBody = await resendRes.text();
      console.log(`[winback ${telefon}] Resend status:`, resendRes.status, "body:", resendBody);

      if (resendRes.ok) {
        await adminClient.from("winback_log").insert({
          telefon, email: c.email, nama: c.nama,
          tarikh_pesanan_terakhir: c.terakhir,
          kod_voucher: voucherSahDisebut ? kodVoucher : null,
        });
        dihantar++;
      }
    }

    return new Response(JSON.stringify({
      dihantar, dilangkauCooldown, dilangkauHad,
      jumlahCalonTidakAktif: calon.length,
    }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  } catch (e) {
    console.error("winback-auto-cron error:", e);
    return new Response(JSON.stringify({ error: String(e?.message || e) }), { status: 500, headers: corsHeaders });
  }
});
