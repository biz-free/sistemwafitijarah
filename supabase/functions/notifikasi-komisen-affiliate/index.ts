// Edge Function: notifikasi-komisen-affiliate
// Dipanggil oleh trigger pg_net (cipta_pendapatan_affiliate, SQL_TAMBAHAN_122)
// SETIAP KALI pemilik sahkan bayaran pesanan yang guna kod affiliate —
// hantar push+emel terus kepada AFFILIATE tersebut (bukan pemilik) bagitahu
// komisen baharu berjaya direkod. Guna Resend (RESEND_API_KEY sedia ada) +
// web-push (VAPID_PRIVATE_KEY sedia ada) — sama corak dgn
// notifikasi-kelulusan-pemilik, tapi sasaran SATU pengguna (affiliate_id),
// bukan semua pemilik.

import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const FROM_EMAIL = "Wafi Tijarah Trading <no-reply@wafitijarahtrading.com>";
const VAPID_PUBLIC_KEY = "BHn9H44ym7-erXGNS-netsYpsVNke8--awcoLbfcughKJHwb54aOEciUEbYDBidGYdGWDkJtBneOVkz3TDXPqDA";

function esc(s: unknown): string {
  return String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c] as string));
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const { affiliate_id, pesanan_id, jumlah_pesanan, jumlah_komisen } = await req.json();
    if (!affiliate_id) {
      return new Response(JSON.stringify({ error: "affiliate_id diperlukan" }), { status: 400, headers: corsHeaders });
    }

    const adminClient = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

    const { data: affiliate } = await adminClient.from("affiliates").select("nama, kod_affiliate").eq("id", affiliate_id).single();
    const { data: userData } = await adminClient.auth.admin.getUserById(affiliate_id);
    const emelAffiliate = userData?.user?.email;

    const jumlahKomisenStr = `RM${Number(jumlah_komisen).toFixed(2)}`;
    const jumlahPesananStr = `RM${Number(jumlah_pesanan).toFixed(2)}`;

    let emelDihantar = false;
    const resendKey = Deno.env.get("RESEND_API_KEY");
    if (resendKey && emelAffiliate) {
      const html = `
        <div style="font-family:sans-serif;max-width:480px;margin:0 auto">
          <h2 style="color:#0D2137">🎉 Komisen Baharu!</h2>
          <p>Assalamualaikum ${esc(affiliate?.nama || "")},</p>
          <p>Tahniah! Pesanan yang guna kod affiliate anda <b>${esc(affiliate?.kod_affiliate || "")}</b> baru sahaja disahkan bayarannya.</p>
          <p><b>Jumlah Pesanan:</b> ${jumlahPesananStr}<br><b>Komisen Anda:</b> ${jumlahKomisenStr}</p>
          <p style="font-size:12px;color:#888">Komisen ni akan boleh dituntut selepas tempoh 14 hari (elak pesanan dibatalkan/dipulangkan). Semak status terkini di dashboard anda.</p>
          <p style="margin-top:20px">
            <a href="https://www.wafitijarahtrading.com/affiliate.html" style="background:#0D2137;color:#fff;padding:10px 20px;border-radius:8px;text-decoration:none">Buka Dashboard Affiliate</a>
          </p>
        </div>`;
      const res = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: { Authorization: `Bearer ${resendKey}`, "Content-Type": "application/json" },
        body: JSON.stringify({ from: FROM_EMAIL, to: [emelAffiliate], subject: `🎉 Komisen Baharu ${jumlahKomisenStr} — Wafi Tijarah Trading`, html }),
      });
      emelDihantar = res.ok;
    }

    let pushDihantar = 0;
    const vapidPrivateKey = Deno.env.get("VAPID_PRIVATE_KEY");
    if (vapidPrivateKey) {
      webpush.setVapidDetails("mailto:wafitijarahtrading@gmail.com", VAPID_PUBLIC_KEY, vapidPrivateKey);
      const { data: subs } = await adminClient.from("push_subscriptions").select("*").eq("user_id", affiliate_id);
      const payload = JSON.stringify({
        title: `🎉 Komisen Baharu ${jumlahKomisenStr}`,
        body: `Pesanan ${jumlahPesananStr} guna kod ${affiliate?.kod_affiliate || ""} baru disahkan.`,
        url: "./affiliate.html",
      });
      for (const s of subs || []) {
        try {
          await webpush.sendNotification({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth_key } }, payload);
          pushDihantar++;
        } catch (err) {
          const kod = (err as { statusCode?: number })?.statusCode;
          if (kod === 404 || kod === 410) await adminClient.from("push_subscriptions").delete().eq("id", s.id);
        }
      }
    }

    return new Response(JSON.stringify({ ok: true, emelDihantar, pushDihantar, pesanan_id }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String((e as Error)?.message || e) }), { status: 500, headers: corsHeaders });
  }
});
