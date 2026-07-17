// Edge Function: easyparcel-track-order
// Dipanggil ON-DEMAND bila pembeli tekan "Jejak" di modal Jejak Pesanan
// (index.html) — panggil EasyParcel API terus untuk dapatkan status TERKINI,
// bukan easyparcel_status yang tersimpan dalam DB (yang cuma direkod SEKALI
// semasa label dijana di easyparcel-book-shipment, dan tak pernah dikemaskini
// selepas itu — lihat komen dalam fungsi tu).
//
// ⚠️ NOTA PENTING: Endpoint EasyParcel untuk query status/tracking TIDAK dapat
// disahkan sepenuhnya daripada dokumentasi rasmi semasa fungsi ni dibina.
// Endpoint di bawah dianggarkan mengikut corak URL yang SAMA & DISAHKAN
// berfungsi untuk shipment/submit_orders (easyparcel-book-shipment). Jika
// panggilan gagal, semak log fungsi ni ("EasyParcel track_orders status: ###
// body: {...}") — respons ralat EasyParcel akan tunjuk endpoint/parameter
// yang betul untuk dilaraskan. Client (index.html) direka supaya SENYAP
// sembunyikan bahagian status live jika panggilan ni gagal — pautan "Jejak di
// Laman Kurier" kekal sebagai jalan fallback yang sentiasa berfungsi.

import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

async function ambilTokenSah(adminClient: ReturnType<typeof createClient>): Promise<string> {
  const { data: auth, error } = await adminClient.from("easyparcel_auth").select("*").eq("id", 1).single();
  if (error || !auth?.access_token) throw new Error("EasyParcel belum disambungkan.");

  const tamatDalam = auth.expires_at ? (new Date(auth.expires_at).getTime() - Date.now()) : Infinity;
  if (tamatDalam > 60_000) return auth.access_token;
  if (!auth.refresh_token) throw new Error("Token EasyParcel telah luput.");

  const clientId = Deno.env.get("EASYPARCEL_CLIENT_ID")!;
  const clientSecret = Deno.env.get("EASYPARCEL_CLIENT_SECRET")!;
  const basicAuth = btoa(`${clientId}:${clientSecret}`);
  const refreshRes = await fetch("https://api.easyparcel.com/oauth/token", {
    method: "POST",
    headers: { "Authorization": `Basic ${basicAuth}`, "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "refresh_token", refresh_token: auth.refresh_token }),
  });
  const refreshData = await refreshRes.json().catch(() => ({} as any));
  if (!refreshRes.ok || !refreshData.access_token) throw new Error("Gagal refresh token EasyParcel.");

  await adminClient.from("easyparcel_auth").update({
    access_token: refreshData.access_token,
    refresh_token: refreshData.refresh_token || auth.refresh_token,
    expires_at: refreshData.expires_at || null,
  }).eq("id", 1);

  return refreshData.access_token;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const { orderId } = await req.json();
    if (!orderId) {
      return new Response(JSON.stringify({ error: "orderId diperlukan" }), { status: 400, headers: corsHeaders });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const adminClient = createClient(supabaseUrl, serviceKey);

    const { data: order, error: orderErr } = await adminClient
      .from("pesanan_edagang")
      .select("no_tracking, nama_kurier")
      .eq("id", orderId)
      .single();
    if (orderErr || !order) {
      return new Response(JSON.stringify({ error: "Pesanan tidak dijumpai" }), { status: 404, headers: corsHeaders });
    }
    if (!order.no_tracking) {
      return new Response(JSON.stringify({ error: "Pesanan ini belum ada label/tracking" }), { status: 400, headers: corsHeaders });
    }

    const accessToken = await ambilTokenSah(adminClient);

    const trackRes = await fetch("https://api.easyparcel.com/open_api/2026-06/shipment/track_orders", {
      method: "POST",
      headers: { "Authorization": `Bearer ${accessToken}`, "Content-Type": "application/json" },
      body: JSON.stringify({ awb_number: [order.no_tracking] }),
    });
    const trackBodyText = await trackRes.text();
    console.log("EasyParcel track_orders status:", trackRes.status, "body:", trackBodyText);
    let trackData: any = {};
    try { trackData = JSON.parse(trackBodyText); } catch { /* biar kosong */ }

    const hasil = trackData?.data?.[0];
    if (!trackRes.ok || !hasil) {
      return new Response(JSON.stringify({ error: "Gagal dapatkan status tracking terkini", detail: trackBodyText }), { status: 502, headers: corsHeaders });
    }

    return new Response(JSON.stringify({
      status: hasil.status || hasil.tracking_status || hasil.latest_status || null,
      nama_kurier: order.nama_kurier,
      no_tracking: order.no_tracking,
    }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  } catch (e) {
    console.error("easyparcel-track-order error:", e);
    return new Response(JSON.stringify({ error: String(e?.message || e) }), { status: 500, headers: corsHeaders });
  }
});
