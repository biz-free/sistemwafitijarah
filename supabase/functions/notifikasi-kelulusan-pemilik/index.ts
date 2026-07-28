// Edge Function: notifikasi-kelulusan-pemilik
// Dipanggil oleh trigger pg_net (notify_pemilik_kelulusan, SQL_TAMBAHAN_65) bila
// ada permohonan BAHARU perlu kelulusan pemilik: permohonan_padam, permohonan_cuti,
// serahan_cash, serahan_produk (reject/ambil) — elak pekerja tunggu lama tanpa
// pemilik sedar ada permohonan menunggu. Guna Resend, sama corak dgn
// hantar-emel-susulan (RESEND_API_KEY secret sedia ada, domain wafitijarahtrading.com
// sudah disahkan).

import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const FROM_EMAIL = "Wafi Tijarah Trading <no-reply@wafitijarahtrading.com>";

function esc(s: unknown): string {
  return String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c] as string));
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const { jenis, pekerja_nama, butiran } = await req.json();
    if (!jenis) {
      return new Response(JSON.stringify({ error: "jenis diperlukan" }), { status: 400, headers: corsHeaders });
    }

    const resendKey = Deno.env.get("RESEND_API_KEY");
    if (!resendKey) {
      return new Response(JSON.stringify({ error: "RESEND_API_KEY belum ditetapkan sebagai secret" }), { status: 500, headers: corsHeaders });
    }

    const adminClient = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

    const { data: pemilikList, error: pemilikErr } = await adminClient
      .from("profiles")
      .select("id")
      .eq("role", "pemilik");
    if (pemilikErr || !pemilikList?.length) {
      return new Response(JSON.stringify({ error: "Tiada akaun pemilik dijumpai" }), { status: 404, headers: corsHeaders });
    }

    const emails: string[] = [];
    for (const p of pemilikList) {
      const { data: userData } = await adminClient.auth.admin.getUserById(p.id);
      if (userData?.user?.email) emails.push(userData.user.email);
    }
    if (!emails.length) {
      return new Response(JSON.stringify({ error: "Tiada emel pemilik dijumpai" }), { status: 404, headers: corsHeaders });
    }

    const html = `
      <div style="font-family:sans-serif;max-width:480px;margin:0 auto">
        <h2 style="color:#0D2137">🔔 Permohonan Baharu Perlu Kelulusan</h2>
        <p><b>Jenis:</b> ${esc(jenis)}</p>
        <p><b>Pekerja:</b> ${esc(pekerja_nama)}</p>
        <p><b>Butiran:</b> ${esc(butiran)}</p>
        <p style="margin-top:20px">
          <a href="https://www.wafitijarahtrading.com/pengurusan.html" style="background:#0D2137;color:#fff;padding:10px 20px;border-radius:8px;text-decoration:none">Buka Sistem Pengurusan</a>
        </p>
        <p style="font-size:11px;color:#888;margin-top:24px">Emel automatik — sila jangan balas.</p>
      </div>`;

    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${resendKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        from: FROM_EMAIL,
        to: emails,
        subject: `🔔 ${jenis} — Perlu Kelulusan`,
        html,
      }),
    });
    const resendResult = await res.json();
    if (!res.ok) {
      return new Response(JSON.stringify({ error: "Resend gagal: " + JSON.stringify(resendResult) }), { status: 502, headers: corsHeaders });
    }

    return new Response(JSON.stringify({ ok: true, sent_to: emails.length }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String((e as Error)?.message || e) }), { status: 500, headers: corsHeaders });
  }
});
