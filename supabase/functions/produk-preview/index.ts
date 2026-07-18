// Edge Function: produk-preview
// Dipanggil bila pautan produk dikongsi (WhatsApp/Facebook/Telegram/Gmail/dll.) — crawler
// bot media sosial tak jalankan JavaScript, jadi meta-tag Open Graph yang diset oleh
// index.html (SPA) selepas dimuatkan TAK akan pernah nampak oleh crawler tersebut.
// Fungsi ni balas SETIAP permintaan dengan HTML statik + meta-tag OG sebenar
// (gambar/nama/harga produk) dari server, tanpa perlu jalankan JS langsung.
//
// NOTA: dulu fungsi ni cuba kesan User-Agent crawler (regex whitelist) dan hantar 302
// redirect terus untuk pelawat biasa. Tapi senarai UA crawler tak lengkap (cth Gmail
// link-preview tak sepadan mana-mana pattern), jadi crawler yang tak dikenali dapat 302
// kosong (tiada meta-tag) dan preview gagal keluar. Sekarang SEMUA permintaan (crawler
// atau bukan) dapat HTML yang sama dengan meta refresh serta-merta — lebih selamat &
// tak perlu jangka setiap crawler baharu, dan pelawat biasa tetap sampai ke laman
// produk dalam masa yang tak ketara (~serta-merta, jauh lebih pantas drpd pemendek
// pautan pihak ketiga yang ada halaman iklan).

import { createClient } from "npm:@supabase/supabase-js@2";

const SITE_URL = "https://www.wafitijarahtrading.com/";

function esc(s: unknown): string {
  return String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c] as string));
}

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const produkId = url.searchParams.get("id") || "";
  const tujuanUrl = produkId ? `${SITE_URL}?produk=${encodeURIComponent(produkId)}` : SITE_URL;

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const sb = createClient(supabaseUrl, anonKey);
    const { data } = await sb.rpc("senarai_produk_awam");
    const produk = (data || []).find((p: { id: string }) => p.id === produkId);

    if (!produk) {
      return new Response(null, { status: 302, headers: { Location: SITE_URL } });
    }

    const tajuk = `${produk.nama} — RM${Number(produk.harga_jual).toFixed(2)} | Wafi Tijarah Trading`;
    const huraian = `${produk.nama} (${produk.kategori || "Produk Halal"}) — RM${Number(produk.harga_jual).toFixed(2)}/${produk.unit}. Produk halal berkualiti, penghantaran ke seluruh Malaysia.`;
    const gambarUrl = produk.gambar_url || `${SITE_URL}logo.png`;

    const html = `<!DOCTYPE html>
<html lang="ms">
<head>
<meta charset="UTF-8">
<title>${esc(tajuk)}</title>
<meta property="og:title" content="${esc(tajuk)}">
<meta property="og:description" content="${esc(huraian)}">
<meta property="og:image" content="${esc(gambarUrl)}">
<meta property="og:url" content="${esc(tujuanUrl)}">
<meta property="og:type" content="product">
<meta name="twitter:card" content="summary_large_image">
<meta http-equiv="refresh" content="0; url=${esc(tujuanUrl)}">
</head>
<body>
<p>Membawa ke <a href="${esc(tujuanUrl)}">${esc(produk.nama)}</a>...</p>
</body>
</html>`;

    return new Response(html, { status: 200, headers: { "Content-Type": "text/html; charset=utf-8" } });
  } catch {
    return new Response(null, { status: 302, headers: { Location: SITE_URL } });
  }
});
