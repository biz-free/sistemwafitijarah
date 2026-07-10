// Edge Function: easyparcel-book-shipment
// Dipanggil oleh STAFF dari pengurusan.html untuk jana label & dapatkan
// no. AWB/tracking sebenar bagi satu pesanan e-dagang, menggunakan kurier
// (service_id) yang telah dipilih pelanggan semasa checkout.
// client_secret & access_token EasyParcel kekal di server (service_role) sahaja.

import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const SUBDIVISION: Record<string, string> = {
  "Johor": "MY-01", "Kedah": "MY-02", "Kelantan": "MY-03", "Melaka": "MY-04",
  "Negeri Sembilan": "MY-05", "Pahang": "MY-06", "Pulau Pinang": "MY-07", "Perak": "MY-08",
  "Perlis": "MY-09", "Selangor": "MY-10", "Terengganu": "MY-11", "Sabah": "MY-12",
  "Sarawak": "MY-13", "W.P. Kuala Lumpur": "MY-14", "W.P. Labuan": "MY-15", "W.P. Putrajaya": "MY-16",
};

function telefonTempatan(raw: string | null | undefined): string {
  const digits = (raw || "").replace(/\D/g, "");
  if (digits.startsWith("60")) return digits.slice(2);
  if (digits.startsWith("0")) return digits.slice(1);
  return digits;
}

async function ambilTokenSah(adminClient: ReturnType<typeof createClient>): Promise<string> {
  const { data: auth, error } = await adminClient.from("easyparcel_auth").select("*").eq("id", 1).single();
  if (error || !auth?.access_token) throw new Error("EasyParcel belum disambungkan.");

  const tamatDalam = auth.expires_at ? (new Date(auth.expires_at).getTime() - Date.now()) : Infinity;
  if (tamatDalam > 60_000) return auth.access_token;

  if (!auth.refresh_token) throw new Error("Token EasyParcel telah luput. Sila sambung semula di Profil > EasyParcel.");

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
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Tiada token log masuk" }), { status: 401, headers: corsHeaders });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    const callerClient = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: authHeader } } });
    const { data: { user }, error: userErr } = await callerClient.auth.getUser();
    if (userErr || !user) {
      return new Response(JSON.stringify({ error: "Token tidak sah" }), { status: 401, headers: corsHeaders });
    }
    const { data: callerProfile } = await callerClient.from("profiles").select("id").eq("id", user.id).single();
    if (!callerProfile) {
      return new Response(JSON.stringify({ error: "Hanya staff dibenarkan jana label penghantaran" }), { status: 403, headers: corsHeaders });
    }

    const { orderId } = await req.json();
    if (!orderId) {
      return new Response(JSON.stringify({ error: "orderId diperlukan" }), { status: 400, headers: corsHeaders });
    }

    const adminClient = createClient(supabaseUrl, serviceKey);

    const { data: order, error: orderErr } = await adminClient.from("pesanan_edagang").select("*").eq("id", orderId).single();
    if (orderErr || !order) {
      return new Response(JSON.stringify({ error: "Pesanan tidak dijumpai" }), { status: 404, headers: corsHeaders });
    }
    if (order.no_tracking) {
      return new Response(JSON.stringify({ error: "Pesanan ini sudah ada label/tracking" }), { status: 400, headers: corsHeaders });
    }
    if (!order.kurier_service_id) {
      return new Response(JSON.stringify({ error: "Pesanan ini tiada kurier dipilih semasa checkout" }), { status: 400, headers: corsHeaders });
    }

    const { data: tetapan } = await adminClient.from("tetapan").select("*").eq("id", 1).single();
    if (!tetapan?.pengirim_alamat || !tetapan?.pengirim_poskod || !tetapan?.pengirim_negeri) {
      return new Response(JSON.stringify({ error: "Alamat pengambilan (pickup) belum lengkap di Tetapan EasyParcel" }), { status: 400, headers: corsHeaders });
    }
    const subdivisionPengirim = SUBDIVISION[tetapan.pengirim_negeri];
    const subdivisionPenerima = SUBDIVISION[order.negeri];
    if (!subdivisionPengirim || !subdivisionPenerima) {
      return new Response(JSON.stringify({ error: "Negeri pengirim/penerima tidak sah" }), { status: 400, headers: corsHeaders });
    }

    const items: any[] = Array.isArray(order.items) ? order.items : [];
    const stokIds = items.map((it) => it.stokId).filter(Boolean);
    const { data: produkList } = await adminClient.from("stok").select("id, berat").in("id", stokIds);
    const beratMap = new Map((produkList || []).map((p: any) => [p.id, p.berat ?? 0.5]));
    let totalBerat = 0;
    const itemPayload = items.map((it) => {
      const berat = beratMap.get(it.stokId) ?? 0.5;
      totalBerat += berat * (Number(it.qty) || 1);
      return {
        content: it.nama || "Produk",
        weight: berat, height: 5, length: 5, width: 5,
        currency_code: "MYR", value: it.harga || 0, quantity: it.qty || 1,
      };
    });
    totalBerat = Math.max(totalBerat, 0.1);

    const accessToken = await ambilTokenSah(adminClient);

    const collectionDate = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString().slice(0, 10);

    const submitPayload = {
      shipment: [{
        reference: order.id,
        service_id: order.kurier_service_id,
        collection_date: collectionDate,
        weight: totalBerat, height: 20, length: 20, width: 20,
        item: itemPayload,
        sender: {
          name: tetapan.pengirim_nama || "Wafi Tijarah Trading",
          phone_number_country_code: "MY",
          phone_number: telefonTempatan(tetapan.pengirim_telefon),
          email: tetapan.pengirim_email || "",
          address_1: tetapan.pengirim_alamat,
          postcode: tetapan.pengirim_poskod,
          city: tetapan.pengirim_bandar || "",
          subdivision_code: subdivisionPengirim,
          country_code: "MY",
        },
        receiver: {
          name: order.pelanggan_nama,
          phone_number_country_code: "MY",
          phone_number: telefonTempatan(order.pelanggan_telefon),
          email: order.pelanggan_email || "",
          address_1: order.alamat,
          postcode: order.poskod,
          city: order.bandar || order.negeri || "",
          subdivision_code: subdivisionPenerima,
          country_code: "MY",
        },
        feature: { sms_tracking: true, email_tracking: true, whatsapp_tracking: false, awb_branding: false },
      }],
    };

    const submitRes = await fetch("https://api.easyparcel.com/open_api/2026-06/shipment/submit_orders", {
      method: "POST",
      headers: { "Authorization": `Bearer ${accessToken}`, "Content-Type": "application/json" },
      body: JSON.stringify(submitPayload),
    });
    const submitBodyText = await submitRes.text();
    console.log("EasyParcel submit_orders status:", submitRes.status, "body:", submitBodyText);
    let submitData: any = {};
    try { submitData = JSON.parse(submitBodyText); } catch { /* biar kosong */ }

    // Bentuk sebenar respons: data[0].shipments[0] — BUKAN data[0] terus.
    // awb_number selalunya null sejurus lepas booking (kurier belum scan parcel);
    // guna shipment_number sebagai rujukan sementara dalam kes tu.
    const shipmentHasil = submitData?.data?.[0]?.shipments?.[0];
    if (!submitRes.ok || shipmentHasil?.status !== "success") {
      await adminClient.from("pesanan_edagang").update({ easyparcel_status: "gagal" }).eq("id", orderId);
      // errors ialah array-dalam-array ikut format EasyParcel — ambil mesej pertama yang sedia untuk staff faham sebab sebenar gagal
      const mesejSebenar = shipmentHasil?.errors?.flat?.()?.[0]?.message;
      return new Response(JSON.stringify({ error: mesejSebenar ? `EasyParcel: ${mesejSebenar}` : "Gagal jana label EasyParcel", detail: submitBodyText }), { status: 502, headers: corsHeaders });
    }
    const awb = shipmentHasil.awb_number || shipmentHasil.shipment_number;

    const { error: updErr } = await adminClient.from("pesanan_edagang").update({
      no_tracking: awb,
      nama_kurier: shipmentHasil.courier || order.nama_kurier,
      easyparcel_awb_url: shipmentHasil.awb_url || null,
      easyparcel_tracking_url: shipmentHasil.tracking_url || null,
      easyparcel_status: "ditempah",
      updated_at: new Date().toISOString(),
    }).eq("id", orderId);
    if (updErr) {
      return new Response(JSON.stringify({ error: "Label dijana tapi gagal simpan ke pesanan: " + updErr.message }), { status: 500, headers: corsHeaders });
    }

    return new Response(JSON.stringify({ success: true, awb }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error("easyparcel-book-shipment error:", e);
    return new Response(JSON.stringify({ error: String(e?.message || e) }), { status: 500, headers: corsHeaders });
  }
});
