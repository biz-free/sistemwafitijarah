// Edge Function: produk-preview-gen
// Dipanggil dari pengurusan.html (bila produk disimpan) untuk jana fail HTML pratonton
// statik (meta-tag Open Graph) bagi satu produk, dan COMMIT fail tu terus ke repo
// GitHub (biz-free/sistemwafitijarah) guna GitHub Contents API — supaya GitHub Pages
// sajikan fail tu di wafitijarahtrading.com/preview/<kod>.html dengan Content-Type
// text/html yang BETUL.
//
// SEBAB pendekatan ni (bukan Edge Function/Storage terus): Supabase SENGAJA menukar
// Content-Type text/html kepada text/plain untuk kandungan yang disajikan dari domain
// kongsi *.supabase.co (both Edge Functions — didokumenkan rasmi — dan juga Storage,
// disahkan secara praktikal) — langkah keselamatan supaya domain kongsi tu tak boleh
// hos kandungan web yang boleh laksana (elak phishing/XSS). Ini bermakna TIADA cara
// dalam Supabase untuk sajikan HTML dengan Content-Type betul. GitHub Pages (domain
// wafitijarahtrading.com sendiri) sajikan .html dengan Content-Type betul secara
// semula jadi, jadi crawler pratonton pautan (WhatsApp/Facebook/Gmail/dll., termasuk
// yang ketat tentang Content-Type) boleh baca meta-tag OG dengan yakin.
//
// Setup wajib: secret GITHUB_TOKEN (Fine-grained Personal Access Token, skop HANYA
// repo biz-free/sistemwafitijarah, kebenaran "Contents: Read and write").

const GITHUB_REPO = "biz-free/sistemwafitijarah";
const GITHUB_BRANCH = "main";
const SITE_URL = "https://www.wafitijarahtrading.com/";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function esc(s: unknown): string {
  return String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c] as string));
}

function toBase64(str: string): string {
  const bytes = new TextEncoder().encode(str);
  let binary = "";
  bytes.forEach((b) => (binary += String.fromCharCode(b)));
  return btoa(binary);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const { produkId } = await req.json();
    if (!produkId) {
      return new Response(JSON.stringify({ error: "produkId diperlukan" }), { status: 400, headers: corsHeaders });
    }

    const githubToken = Deno.env.get("GITHUB_TOKEN");
    if (!githubToken) {
      return new Response(JSON.stringify({ error: "GITHUB_TOKEN belum ditetapkan sebagai secret" }), { status: 500, headers: corsHeaders });
    }

    const { createClient } = await import("npm:@supabase/supabase-js@2");
    const adminClient = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

    const { data: produk, error: produkErr } = await adminClient
      .from("stok")
      .select("id, nama, kategori, unit, harga_jual, gambar_url")
      .eq("id", produkId)
      .single();
    if (produkErr || !produk) {
      return new Response(JSON.stringify({ error: "Produk tidak dijumpai" }), { status: 404, headers: corsHeaders });
    }

    const tujuanUrl = `${SITE_URL}?produk=${encodeURIComponent(produk.id)}`;
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

    const path = `preview/${produk.id}.html`;
    const apiUrl = `https://api.github.com/repos/${GITHUB_REPO}/contents/${path}`;
    const ghHeaders = {
      "Authorization": `Bearer ${githubToken}`,
      "Accept": "application/vnd.github+json",
      "User-Agent": "wafi-tijarah-produk-preview-gen",
      "Content-Type": "application/json",
    };

    // Semak sama ada fail dah wujud (perlukan sha untuk update)
    const getRes = await fetch(`${apiUrl}?ref=${GITHUB_BRANCH}`, { headers: ghHeaders });
    let sha: string | undefined;
    if (getRes.ok) {
      const existing = await getRes.json();
      sha = existing.sha;
    } else if (getRes.status !== 404) {
      const errBody = await getRes.text();
      console.log("GitHub GET status:", getRes.status, "body:", errBody);
      return new Response(JSON.stringify({ error: "Gagal semak fail sedia ada di GitHub" }), { status: 502, headers: corsHeaders });
    }

    const putRes = await fetch(apiUrl, {
      method: "PUT",
      headers: ghHeaders,
      body: JSON.stringify({
        message: `Kemaskini pratonton produk ${produk.id}`,
        content: toBase64(html),
        branch: GITHUB_BRANCH,
        ...(sha ? { sha } : {}),
      }),
    });
    if (!putRes.ok) {
      const errBody = await putRes.text();
      console.log("GitHub PUT status:", putRes.status, "body:", errBody);
      return new Response(JSON.stringify({ error: "Gagal commit fail pratonton ke GitHub" }), { status: 502, headers: corsHeaders });
    }

    return new Response(JSON.stringify({ url: `${SITE_URL}preview/${produk.id}.html` }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e?.message || e) }), { status: 500, headers: corsHeaders });
  }
});
