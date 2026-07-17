// Edge Function: billplz-create-bill
// Dipanggil dari checkout (index.html DAN pesan.html) selepas pesanan disimpan,
// bila pelanggan/kedai pilih "Bayar Online (FPX/Kad)" — cipta Bill Billplz &
// pulangkan URL bayaran untuk redirect. Secret Key Billplz kekal di server
// (service_role/secret sahaja) — tidak pernah masuk kod client-side.
// Sokong DUA jenis pesanan: pesanan_edagang (index.html) & pre_order (pesan.html)
// — cuba pesanan_edagang dahulu, fallback ke pre_order jika tiada padanan.

import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const REDIRECT_URL_ASAS = "https://www.wafitijarahtrading.com/";
const REDIRECT_URL_PESAN = "https://www.wafitijarahtrading.com/pesan.html";
const CALLBACK_URL = "https://smepriytkoxkmpvjvvzq.supabase.co/functions/v1/billplz-webhook";

function telefonBillplz(raw: string | null | undefined): string {
  const digits = (raw || "").replace(/\D/g, "");
  if (digits.startsWith("60")) return digits;
  if (digits.startsWith("0")) return "60" + digits.slice(1);
  return "60" + digits;
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

    let orderTable = "pesanan_edagang";
    let { data: order, error: orderErr } = await adminClient.from("pesanan_edagang").select("*").eq("id", orderId).single();
    if (orderErr || !order) {
      orderTable = "pre_order";
      ({ data: order, error: orderErr } = await adminClient.from("pre_order").select("*").eq("id", orderId).single());
    }
    if (orderErr || !order) {
      return new Response(JSON.stringify({ error: "Pesanan tidak dijumpai" }), { status: 404, headers: corsHeaders });
    }
    if (order.billplz_bill_id) {
      return new Response(JSON.stringify({ error: "Bill Billplz sudah wujud untuk pesanan ini" }), { status: 400, headers: corsHeaders });
    }

    const baseUrl = Deno.env.get("BILLPLZ_BASE_URL") || "https://www.billplz-sandbox.com";
    const secretKey = Deno.env.get("BILLPLZ_SECRET_KEY")!;
    const collectionId = Deno.env.get("BILLPLZ_COLLECTION_ID")!;
    const basicAuth = btoa(`${secretKey}:`);

    const nama = orderTable === "pre_order" ? order.kedai_nama : order.pelanggan_nama;
    const telefon = orderTable === "pre_order" ? order.kedai_telefon : order.pelanggan_telefon;
    const emel = orderTable === "pre_order" ? null : order.pelanggan_email;
    const jumlah = orderTable === "pre_order" ? order.jumlah_selepas_diskaun : order.jumlah;
    const redirectAsas = orderTable === "pre_order" ? REDIRECT_URL_PESAN : REDIRECT_URL_ASAS;

    const body = new URLSearchParams({
      collection_id: collectionId,
      email: emel || "pelanggan@wafitijarahtrading.com",
      mobile: telefonBillplz(telefon),
      name: nama,
      amount: String(Math.round(jumlah * 100)),
      callback_url: CALLBACK_URL,
      redirect_url: `${redirectAsas}?billplz_pesanan=${encodeURIComponent(orderId)}`,
      description: `Pesanan ${orderId} - Wafi Tijarah Trading`,
      reference_1_label: "Pesanan",
      reference_1: orderId,
    });

    const billRes = await fetch(`${baseUrl}/api/v3/bills`, {
      method: "POST",
      headers: { "Authorization": `Basic ${basicAuth}`, "Content-Type": "application/x-www-form-urlencoded" },
      body: body.toString(),
    });
    const billBodyText = await billRes.text();
    console.log("Billplz create bill status:", billRes.status, "body:", billBodyText);
    let billData: any = {};
    try { billData = JSON.parse(billBodyText); } catch { /* biar kosong */ }

    if (!billRes.ok || !billData?.id || !billData?.url) {
      const billplzMsg = String(billData?.error?.message?.[0] || "");
      let mesejRamah = "Gagal sediakan bayaran online. Sila cuba lagi atau hubungi kami.";
      if (/mobile/i.test(billplzMsg)) {
        mesejRamah = "Nombor telefon yang dimasukkan tidak sah. Sila semak semula & pastikan lengkap (cth: 0123456789).";
      } else if (/email/i.test(billplzMsg)) {
        mesejRamah = "Alamat e-mel yang dimasukkan tidak sah.";
      }
      return new Response(JSON.stringify({ error: mesejRamah, detail: billBodyText }), { status: 502, headers: corsHeaders });
    }

    const kemaskini: Record<string, unknown> = orderTable === "pre_order"
      ? { billplz_bill_id: billData.id, bayar_metod: "billplz" }
      : { billplz_bill_id: billData.id, kaedah_bayaran: "billplz", updated_at: new Date().toISOString() };
    const { error: updErr } = await adminClient.from(orderTable).update(kemaskini).eq("id", orderId);
    if (updErr) {
      return new Response(JSON.stringify({ error: "Bill dicipta tapi gagal simpan ke pesanan: " + updErr.message }), { status: 500, headers: corsHeaders });
    }

    return new Response(JSON.stringify({ url: billData.url }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error("billplz-create-bill error:", e);
    return new Response(JSON.stringify({ error: String(e?.message || e) }), { status: 500, headers: corsHeaders });
  }
});
