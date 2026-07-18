// Edge Function: shorten-link
// Pendekkan pautan kongsi produk (guna TinyURL — percuma, tiada API key/akaun
// diperlukan). Dipanggil dari client sebab TinyURL API tak benarkan CORS
// terus dari browser, jadi perlu proksi melalui server (Edge Function ni
// tiada sekatan CORS bila panggil API luar).
//
// NOTA: is.gd dicuba sebagai gantian (untuk elak halaman iklan TinyURL) tapi
// ditolak balik ke TinyURL sebab is.gd menolak panggilan dari IP awan
// Supabase ("Error, database insert failed") — tak boleh dipercayai untuk
// panggilan server-ke-server. Kekal guna TinyURL buat masa ini sehingga
// shortener sendiri (di domain wafitijarahtrading.com) dibina.

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const { url } = await req.json();
    if (!url) {
      return new Response(JSON.stringify({ error: "url diperlukan" }), { status: 400, headers: corsHeaders });
    }

    const res = await fetch(`https://tinyurl.com/api-create.php?url=${encodeURIComponent(url)}`);
    const pendek = (await res.text()).trim();

    if (!res.ok || !pendek.startsWith("http")) {
      return new Response(JSON.stringify({ error: "Gagal pendekkan pautan" }), { status: 502, headers: corsHeaders });
    }

    return new Response(JSON.stringify({ url: pendek }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e?.message || e) }), { status: 500, headers: corsHeaders });
  }
});
