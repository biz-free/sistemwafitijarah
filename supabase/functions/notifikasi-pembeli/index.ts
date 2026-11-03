// Edge Function: notifikasi-pembeli
// Hantar emel kepada PEMBELI (Resend) untuk pesanan e-dagang:
//   jenis 'pengesahan'  — selepas pesanan dibuat (dipanggil dari index.html, tanpa log masuk)
//   jenis 'penghantaran' — selepas no. tracking dijana (dipanggil dari easyparcel-book-shipment)
// Setiap jenis dihantar SEKALI sahaja (penanda emel_*_dihantar) — selamat walau dipanggil
// berulang kali oleh orang lain. Emel dihantar HANYA ke emel yang direkod pada pesanan,
// jadi pemanggil tak boleh ubah penerima.
// Deploy: npx supabase functions deploy notifikasi-pembeli --no-verify-jwt

import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const FROM_EMAIL = "Wafi Tijarah Trading <no-reply@wafitijarahtrading.com>";
const LAMAN = "https://www.wafitijarahtrading.com";
const WA = "https://wa.me/60146363831";

const esc = (s: unknown) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c] as string));

function langkahSeterusnya(o: any): string {
  if (o.kaedah_bayaran === "billplz") {
    return o.status_bayaran === "disahkan"
      ? "Bayaran anda telah disahkan. Kami akan hantar emel lagi bersama no. tracking sebaik parcel diserahkan kepada kurier."
      : "Sila selesaikan bayaran dalam talian. Sebaik bayaran disahkan, no. tracking dijana automatik dan dihantar kepada anda.";
  }
  if (o.kaedah_bayaran === "transfer") return "Kami akan semak bukti pindahan anda (waktu bekerja, biasanya dalam 1 jam). Selepas disahkan, parcel diproses & no. tracking dihantar.";
  return "Pihak kami akan hubungi anda untuk sahkan penghantaran, dan no. tracking dihantar sebaik parcel diserahkan kepada kurier.";
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const { orderId, jenis } = await req.json();
    if (!orderId || !["pengesahan", "penghantaran"].includes(jenis)) {
      return new Response(JSON.stringify({ error: "orderId & jenis (pengesahan|penghantaran) diperlukan" }), { status: 400, headers: corsHeaders });
    }
    const resendKey = Deno.env.get("RESEND_API_KEY");
    if (!resendKey) return new Response(JSON.stringify({ error: "RESEND_API_KEY belum ditetapkan" }), { status: 500, headers: corsHeaders });

    const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const { data: o } = await admin.from("pesanan_edagang").select("*").eq("id", orderId).single();
    if (!o) return new Response(JSON.stringify({ error: "Pesanan tidak dijumpai" }), { status: 404, headers: corsHeaders });
    if (!o.pelanggan_email) return new Response(JSON.stringify({ skipped: "tiada emel" }), { status: 200, headers: corsHeaders });

    const lajur = jenis === "pengesahan" ? "emel_pengesahan_dihantar" : "emel_penghantaran_dihantar";
    if (o[lajur]) return new Response(JSON.stringify({ skipped: "sudah dihantar" }), { status: 200, headers: corsHeaders });
    if (jenis === "penghantaran" && !o.no_tracking) return new Response(JSON.stringify({ skipped: "belum ada tracking" }), { status: 200, headers: corsHeaders });
    // Cegah penyalahgunaan: emel pengesahan hanya untuk pesanan <2 jam lepas dibuat
    if (jenis === "pengesahan" && Date.now() - new Date(o.created_at).getTime() > 2 * 3600_000) {
      return new Response(JSON.stringify({ skipped: "terlalu lama" }), { status: 200, headers: corsHeaders });
    }

    const itemsHtml = (o.items || []).map((it: any) => `<li>${esc(it.nama)} ×${esc(it.qty)}</li>`).join("");
    const linkStatus = `${LAMAN}/?semak=${encodeURIComponent(o.id)}`;
    const kotak = (isi: string) => `
      <div style="font-family:Arial,sans-serif;color:#16241D;max-width:480px;margin:0 auto">
        <h2 style="color:#0B3D2E">Wafi Tijarah Trading</h2>
        <p>Assalamualaikum ${esc(o.pelanggan_nama)},</p>${isi}
        <p><a href="${linkStatus}" style="background:#0B3D2E;color:#fff;padding:10px 18px;border-radius:8px;text-decoration:none;display:inline-block">Semak Status Pesanan</a></p>
        <p style="font-size:12px;color:#5C7A6C">Ada soalan? Balas emel ini atau <a href="${WA}">WhatsApp kami</a> dengan nombor pesanan ${esc(o.id)}.</p>
      </div>`;

    let subject: string, html: string;
    if (jenis === "pengesahan") {
      subject = `Pesanan ${o.id} Diterima — Wafi Tijarah Trading`;
      html = kotak(`
        <p>Terima kasih! Pesanan anda telah diterima.</p>
        <p><b>No. Pesanan: ${esc(o.id)}</b><br>Jumlah: <b>RM${Number(o.jumlah).toFixed(2)}</b></p>
        <ul>${itemsHtml}</ul>
        <p><b>Langkah seterusnya:</b> ${langkahSeterusnya(o)}</p>`);
    } else {
      subject = `Pesanan ${o.id} Telah Dihantar — No. Tracking ${o.no_tracking}`;
      html = kotak(`
        <p>Berita baik — pesanan <b>${esc(o.id)}</b> telah ditempah dengan kurier${o.nama_kurier ? ` <b>${esc(o.nama_kurier)}</b>` : ""}.</p>
        <p><b>No. Tracking: ${esc(o.no_tracking)}</b></p>
        <ul>${itemsHtml}</ul>
        ${o.easyparcel_tracking_url ? `<p><a href="${esc(o.easyparcel_tracking_url)}">Jejak terus di laman kurier</a></p>` : ""}
        <p style="font-size:12px;color:#5C7A6C">Status mungkin mengambil masa sedikit untuk dikemas kini selepas kurier mengambil parcel.</p>`);
    }

    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${resendKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({ from: FROM_EMAIL, to: [o.pelanggan_email], subject, html }),
    });
    const body = await res.text();
    console.log("notifikasi-pembeli", jenis, o.id, res.status, body);
    if (!res.ok) return new Response(JSON.stringify({ error: "Gagal hantar emel" }), { status: 502, headers: corsHeaders });

    await admin.from("pesanan_edagang").update({ [lajur]: new Date().toISOString() }).eq("id", o.id);
    return new Response(JSON.stringify({ ok: true }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  } catch (e) {
    return new Response(JSON.stringify({ error: String((e as Error)?.message || e) }), { status: 500, headers: corsHeaders });
  }
});
