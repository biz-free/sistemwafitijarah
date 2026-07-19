// Edge Function: hantar-emel-susulan
// Dipanggil dari pengurusan.html (butang "📧 Emel Susulan" pada pesanan e-dagang
// yang belum/gagal bayar) — hantar emel peringatan kepada pelanggan supaya
// selesaikan pembayaran, guna Resend (https://resend.com).
//
// Setup wajib: secret RESEND_API_KEY (daftar akaun percuma di resend.com, sahkan
// domain wafitijarahtrading.com di bahagian "Domains" Resend supaya emel boleh
// dihantar dari alamat @wafitijarahtrading.com).

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
    const { orderId } = await req.json();
    if (!orderId) {
      return new Response(JSON.stringify({ error: "orderId diperlukan" }), { status: 400, headers: corsHeaders });
    }

    const resendKey = Deno.env.get("RESEND_API_KEY");
    if (!resendKey) {
      return new Response(JSON.stringify({ error: "RESEND_API_KEY belum ditetapkan sebagai secret" }), { status: 500, headers: corsHeaders });
    }

    const adminClient = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

    const { data: order, error: orderErr } = await adminClient
      .from("pesanan_edagang")
      .select("id, pelanggan_nama, pelanggan_email, jumlah, items, kaedah_bayaran, status_bayaran")
      .eq("id", orderId)
      .single();
    if (orderErr || !order) {
      return new Response(JSON.stringify({ error: "Pesanan tidak dijumpai" }), { status: 404, headers: corsHeaders });
    }
    if (!order.pelanggan_email) {
      return new Response(JSON.stringify({ error: "Pesanan ini tiada alamat emel pelanggan" }), { status: 400, headers: corsHeaders });
    }
    if (order.status_bayaran === "disahkan") {
      return new Response(JSON.stringify({ error: "Pesanan ini sudah dibayar — tiada susulan diperlukan" }), { status: 400, headers: corsHeaders });
    }

    const { data: tetapan } = await adminClient.from("tetapan").select("butiran_bank").eq("id", 1).single();

    const itemsStr = (order.items || []).map((it: { nama: string; qty: number }) => `${it.nama} ×${it.qty}`).join(", ");
    const bankInfo = order.kaedah_bayaran !== "billplz" && tetapan?.butiran_bank
      ? `<p><b>Butiran Akaun Bank:</b><br>${esc(tetapan.butiran_bank).replace(/\n/g, "<br>")}</p>`
      : "";
    const linkCheckout = "https://www.wafitijarahtrading.com/";

    const html = `
      <div style="font-family:Arial,sans-serif;color:#16241D;max-width:480px;margin:0 auto">
        <h2 style="color:#0B3D2E">Wafi Tijarah Trading</h2>
        <p>Assalamualaikum ${esc(order.pelanggan_nama)},</p>
        <p>Pesanan anda <b>${esc(order.id)}</b> (${esc(itemsStr)}) sejumlah <b>RM${Number(order.jumlah).toFixed(2)}</b> masih belum disahkan pembayarannya.</p>
        <p>Sila selesaikan pembayaran secepat mungkin supaya pesanan anda dapat diproses.</p>
        ${bankInfo}
        <p><a href="${linkCheckout}" style="background:#0B3D2E;color:#fff;padding:10px 18px;border-radius:8px;text-decoration:none;display:inline-block">Layari Kedai Online</a></p>
        <p style="font-size:12px;color:#5C7A6C">Jika anda sudah membuat pembayaran, sila abaikan emel ini atau hubungi kami untuk pengesahan.</p>
      </div>`;

    const resendRes = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { "Authorization": `Bearer ${resendKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        from: FROM_EMAIL,
        to: [order.pelanggan_email],
        subject: `Susulan Pembayaran Pesanan ${order.id} — Wafi Tijarah Trading`,
        html,
      }),
    });
    const resendBody = await resendRes.text();
    console.log("Resend status:", resendRes.status, "body:", resendBody);

    if (!resendRes.ok) {
      let mesej = "Gagal hantar emel";
      try { const parsed = JSON.parse(resendBody); if (parsed?.message) mesej = parsed.message; } catch { /* biar mesej asal */ }
      return new Response(JSON.stringify({ error: mesej }), { status: 502, headers: corsHeaders });
    }

    return new Response(JSON.stringify({ email: order.pelanggan_email }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e?.message || e) }), { status: 500, headers: corsHeaders });
  }
});
