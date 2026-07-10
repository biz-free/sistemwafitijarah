// Edge Function: easyparcel-quotation
// Dipanggil dari borang checkout (index.html) untuk dapatkan kadar
// penghantaran SEBENAR daripada EasyParcel (gantikan kadar zon rata).
// Berat dikira di SINI (server-side) daripada jadual `stok`, bukan dipercayai
// terus dari client — supaya pelanggan tak boleh "tipu" berat untuk dapat
// kadar lebih murah. client_secret EasyParcel tidak pernah terdedah ke client.

import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// ISO 3166-2:MY — padanan nama negeri (Bahasa Malaysia, sama seperti pilihan di borang) ke kod EasyParcel
const SUBDIVISION: Record<string, string> = {
  "Johor": "MY-01",
  "Kedah": "MY-02",
  "Kelantan": "MY-03",
  "Melaka": "MY-04",
  "Negeri Sembilan": "MY-05",
  "Pahang": "MY-06",
  "Pulau Pinang": "MY-07",
  "Perak": "MY-08",
  "Perlis": "MY-09",
  "Selangor": "MY-10",
  "Terengganu": "MY-11",
  "Sabah": "MY-12",
  "Sarawak": "MY-13",
  "W.P. Kuala Lumpur": "MY-14",
  "W.P. Labuan": "MY-15",
  "W.P. Putrajaya": "MY-16",
};

async function ambilTokenSah(adminClient: ReturnType<typeof createClient>): Promise<string> {
  const { data: auth, error } = await adminClient.from("easyparcel_auth").select("*").eq("id", 1).single();
  if (error || !auth?.access_token) throw new Error("EasyParcel belum disambungkan. Sila sambung di Profil > EasyParcel dahulu.");

  const tamatDalam = auth.expires_at ? (new Date(auth.expires_at).getTime() - Date.now()) : Infinity;
  if (tamatDalam > 60_000) return auth.access_token;

  // Token hampir/sudah luput — cuba refresh
  if (!auth.refresh_token) throw new Error("Token EasyParcel telah luput dan tiada refresh_token. Sila sambung semula di Profil > EasyParcel.");

  const clientId = Deno.env.get("EASYPARCEL_CLIENT_ID")!;
  const clientSecret = Deno.env.get("EASYPARCEL_CLIENT_SECRET")!;
  const basicAuth = btoa(`${clientId}:${clientSecret}`);
  const refreshRes = await fetch("https://api.easyparcel.com/oauth/token", {
    method: "POST",
    headers: { "Authorization": `Basic ${basicAuth}`, "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "refresh_token", refresh_token: auth.refresh_token }),
  });
  const refreshBody = await refreshRes.text();
  console.log("EasyParcel refresh token status:", refreshRes.status, "body:", refreshBody);
  let refreshData: any = {};
  try { refreshData = JSON.parse(refreshBody); } catch { /* biar kosong */ }
  if (!refreshRes.ok || !refreshData.access_token) {
    throw new Error("Gagal refresh token EasyParcel. Sila sambung semula di Profil > EasyParcel.");
  }

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
    const { items, negeri, poskod, subjumlah } = await req.json();
    if (!Array.isArray(items) || !items.length || !negeri || !poskod) {
      return new Response(JSON.stringify({ error: "items, negeri & poskod diperlukan" }), { status: 400, headers: corsHeaders });
    }
    const subdivisionPenerima = SUBDIVISION[negeri];
    if (!subdivisionPenerima) {
      return new Response(JSON.stringify({ error: "Negeri tidak dikenali" }), { status: 400, headers: corsHeaders });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const adminClient = createClient(supabaseUrl, serviceKey);

    const { data: tetapan } = await adminClient.from("tetapan").select("pengirim_poskod, pengirim_negeri").eq("id", 1).single();
    if (!tetapan?.pengirim_poskod || !tetapan?.pengirim_negeri) {
      return new Response(JSON.stringify({ error: "Alamat pengambilan (pickup) belum ditetapkan oleh kedai." }), { status: 400, headers: corsHeaders });
    }
    const subdivisionPengirim = SUBDIVISION[tetapan.pengirim_negeri];
    if (!subdivisionPengirim) {
      return new Response(JSON.stringify({ error: "Negeri pengirim (tetapan kedai) tidak sah" }), { status: 400, headers: corsHeaders });
    }

    // Kira berat sebenar daripada jadual stok (server-side — tak percaya client)
    const stokIds = items.map((it: any) => it.stokId).filter(Boolean);
    const { data: produkList } = await adminClient.from("stok").select("id, berat").in("id", stokIds);
    const beratMap = new Map((produkList || []).map((p: any) => [p.id, p.berat ?? 0.5]));
    let totalBerat = 0;
    for (const it of items) {
      const berat = beratMap.get(it.stokId) ?? 0.5;
      totalBerat += berat * (Number(it.qty) || 1);
    }
    totalBerat = Math.max(totalBerat, 0.1);

    const accessToken = await ambilTokenSah(adminClient);

    const quotePayload = {
      shipment: [{
        sender: { postcode: tetapan.pengirim_poskod, subdivision_code: subdivisionPengirim, country: "MY" },
        receiver: { postcode: poskod, subdivision_code: subdivisionPenerima, country: "MY" },
        weight: totalBerat,
        width: 20, length: 20, height: 20,
        parcel_value: Number(subjumlah) || 0,
      }],
    };

    const quoteRes = await fetch("https://api.easyparcel.com/open_api/2026-06/shipment/quotations", {
      method: "POST",
      headers: { "Authorization": `Bearer ${accessToken}`, "Content-Type": "application/json" },
      body: JSON.stringify(quotePayload),
    });
    const quoteBodyText = await quoteRes.text();
    console.log("EasyParcel quotation status:", quoteRes.status, "body:", quoteBodyText);
    let quoteData: any = {};
    try { quoteData = JSON.parse(quoteBodyText); } catch { /* biar kosong */ }

    const hasil = quoteData?.data?.[0];
    if (!quoteRes.ok || hasil?.status !== "success" || !Array.isArray(hasil?.quotations)) {
      return new Response(JSON.stringify({ error: "Gagal dapatkan kadar penghantaran daripada EasyParcel", detail: quoteBodyText }), { status: 502, headers: corsHeaders });
    }

    const KOS_PEMBUNGKUSAN = 2; // RM2 kos packaging tersembunyi — dimasukkan terus dalam kos penghantaran dipaparkan
    let senarai = hasil.quotations
      .filter((q: any) => q.courier?.is_dropoff === true)
      .map((q: any) => ({
        service_id: q.courier?.service_id,
        courier_name: q.courier?.courier_name,
        service_name: q.courier?.service_name,
        courier_logo: q.courier?.courier_logo || null,
        harga: (parseFloat(q.pricing?.total_amount) || 0) + KOS_PEMBUNGKUSAN,
      }))
      .filter((q: any) => q.service_id)
      .sort((a: any, b: any) => a.harga - b.harga);

    // Satu pilihan sahaja setiap kurier (harga termurah bagi kurier tu)
    const dilihat = new Set<string>();
    senarai = senarai.filter((q: any) => {
      if (dilihat.has(q.courier_name)) return false;
      dilihat.add(q.courier_name);
      return true;
    }).slice(0, 6);

    return new Response(JSON.stringify({ kadar: senarai }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error("easyparcel-quotation error:", e);
    return new Response(JSON.stringify({ error: String(e?.message || e) }), { status: 500, headers: corsHeaders });
  }
});
