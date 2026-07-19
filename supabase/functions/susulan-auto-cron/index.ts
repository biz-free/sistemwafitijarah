// Edge Function: susulan-auto-cron
// Dipanggil SEKALI SEHARI oleh pg_cron (bukan dari pengurusan.html/index.html) —
// semak semua pesanan e-dagang yang belum bayar (status_bayaran='menunggu'),
// hantar emel susulan (Resend) jika belum cecah 3 kali, atau batalkan pesanan
// secara automatik jika sudah cecah 3 kali & masih belum bayar. Data pembeli
// KEKAL direkod (baris tak dipadam — cuma status_pesanan ditukar ke
// 'dibatalkan') dan voucher (jika digunakan) dibebaskan untuk guna semula.
//
// Setup wajib: secret RESEND_API_KEY (sama seperti hantar-emel-susulan),
// secret CRON_SECRET (rentetan rawak — dipadankan dengan header yang dihantar
// oleh jadual pg_cron, elak sesiapa panggil fungsi ni terus dari luar).

import { createClient } from "npm:@supabase/supabase-js@2";

const FROM_EMAIL = "Wafi Tijarah Trading <no-reply@wafitijarahtrading.com>";
const HAD_SUSULAN = 3;

function esc(s: unknown): string {
  return String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c] as string));
}

async function hantarEmel(resendKey: string, order: any, butiranBank: string | null): Promise<boolean> {
  const itemsStr = (order.items || []).map((it: { nama: string; qty: number }) => `${it.nama} ×${it.qty}`).join(", ");
  const bankInfo = order.kaedah_bayaran !== "billplz" && butiranBank
    ? `<p><b>Butiran Akaun Bank:</b><br>${esc(butiranBank).replace(/\n/g, "<br>")}</p>`
    : "";
  const billplzBaseUrl = Deno.env.get("BILLPLZ_BASE_URL") || "https://www.billplz-sandbox.com";
  const linkCheckout = order.kaedah_bayaran === "billplz" && order.billplz_bill_id
    ? `${billplzBaseUrl}/bills/${order.billplz_bill_id}`
    : "https://www.wafitijarahtrading.com/";
  const labelButang = order.kaedah_bayaran === "billplz" && order.billplz_bill_id
    ? "💳 Teruskan Pembayaran Sekarang"
    : "Layari Kedai Online";
  const baki = HAD_SUSULAN - order.bilangan_susulan;

  const html = `
    <div style="font-family:Arial,sans-serif;color:#16241D;max-width:480px;margin:0 auto">
      <h2 style="color:#0B3D2E">Wafi Tijarah Trading</h2>
      <p>Assalamualaikum ${esc(order.pelanggan_nama)},</p>
      <p>Pesanan anda <b>${esc(order.id)}</b> (${esc(itemsStr)}) sejumlah <b>RM${Number(order.jumlah).toFixed(2)}</b> masih belum disahkan pembayarannya.</p>
      <p>Sila selesaikan pembayaran secepat mungkin supaya pesanan anda dapat diproses.</p>
      ${bankInfo}
      <p><a href="${linkCheckout}" style="background:#0B3D2E;color:#fff;padding:10px 18px;border-radius:8px;text-decoration:none;display:inline-block">${labelButang}</a></p>
      <p style="font-size:12px;color:#5C7A6C">${baki > 0 ? `Susulan automatik ${order.bilangan_susulan + 1}/${HAD_SUSULAN} — jika bayaran tak diterima selepas ${baki} susulan lagi, pesanan ini akan dibatalkan automatik.` : `Ini susulan terakhir (${HAD_SUSULAN}/${HAD_SUSULAN}) — pesanan akan dibatalkan automatik esok jika bayaran masih belum diterima.`}</p>
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
  console.log(`[${order.id}] Resend status:`, resendRes.status, "body:", resendBody);
  return resendRes.ok;
}

Deno.serve(async (req) => {
  try {
    const cronSecret = Deno.env.get("CRON_SECRET");
    if (cronSecret && req.headers.get("x-cron-secret") !== cronSecret) {
      return new Response(JSON.stringify({ error: "Tidak dibenarkan" }), { status: 401 });
    }

    const resendKey = Deno.env.get("RESEND_API_KEY");
    if (!resendKey) {
      return new Response(JSON.stringify({ error: "RESEND_API_KEY belum ditetapkan sebagai secret" }), { status: 500 });
    }

    const adminClient = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

    const { data: tetapan } = await adminClient.from("tetapan").select("butiran_bank").eq("id", 1).single();

    const sehariLalu = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
    const { data: pesananList, error: qErr } = await adminClient
      .from("pesanan_edagang")
      .select("id, pelanggan_nama, pelanggan_email, pelanggan_telefon, jumlah, items, kaedah_bayaran, kod_baucar, bilangan_susulan, susulan_terakhir, billplz_bill_id, created_at")
      .eq("status_bayaran", "menunggu")
      .neq("status_pesanan", "dibatalkan")
      .not("pelanggan_email", "is", null);

    if (qErr) {
      return new Response(JSON.stringify({ error: qErr.message }), { status: 500 });
    }

    let dihantar = 0, dibatalkan = 0, dilangkau = 0;

    for (const order of pesananList || []) {
      const rujukanMasa = order.susulan_terakhir || order.created_at;
      const sudahSehari = new Date(rujukanMasa) <= new Date(sehariLalu);
      if (!sudahSehari) { dilangkau++; continue; }

      if (order.bilangan_susulan >= HAD_SUSULAN) {
        // Cecah had susulan & masih belum bayar — batalkan automatik.
        // Data pembeli KEKAL (baris tak dipadam), voucher dibebaskan jika digunakan.
        if (order.kod_baucar) {
          await adminClient.from("baucar_guna").delete().eq("kod", order.kod_baucar).eq("telefon", order.pelanggan_telefon);
          const { data: bc } = await adminClient.from("baucar").select("bilangan_guna").eq("kod", order.kod_baucar).single();
          if (bc) await adminClient.from("baucar").update({ bilangan_guna: Math.max(0, (bc.bilangan_guna || 0) - 1) }).eq("kod", order.kod_baucar);
        }
        await adminClient.from("pesanan_edagang").update({
          status_pesanan: "dibatalkan",
          kod_baucar: null,
          updated_at: new Date().toISOString(),
        }).eq("id", order.id);
        dibatalkan++;
        continue;
      }

      const berjaya = await hantarEmel(resendKey, order, tetapan?.butiran_bank || null);
      if (berjaya) {
        await adminClient.from("pesanan_edagang").update({
          bilangan_susulan: order.bilangan_susulan + 1,
          susulan_terakhir: new Date().toISOString(),
        }).eq("id", order.id);
        dihantar++;
      }
    }

    return new Response(JSON.stringify({ dihantar, dibatalkan, dilangkau, jumlahDiperiksa: (pesananList || []).length }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error("susulan-auto-cron error:", e);
    return new Response(JSON.stringify({ error: String(e?.message || e) }), { status: 500 });
  }
});
