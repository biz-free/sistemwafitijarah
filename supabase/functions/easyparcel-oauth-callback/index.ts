// Edge Function: easyparcel-oauth-callback
// Redirect URI berdaftar untuk app OAuth EasyParcel. EasyParcel hantar
// pengguna (browser) ke sini selepas mereka log masuk & benarkan akses —
// TIADA token log masuk Supabase pada permintaan ini (ia bukan panggilan
// dari kod app, tapi redirect terus dari EasyParcel), jadi fungsi ini
// MESTI dideploy dengan --no-verify-jwt.
//
// client_secret EasyParcel HANYA hidup sebagai secret Edge Function di
// sini — tidak pernah masuk ke mana-mana fail client-side.

import { createClient } from "npm:@supabase/supabase-js@2";

const REDIRECT_BALIK_BERJAYA = "https://www.wafitijarahtrading.com/pengurusan.html?easyparcel=berjaya";
const REDIRECT_BALIK_GAGAL = "https://www.wafitijarahtrading.com/pengurusan.html?easyparcel=gagal";
// MESTI sama persis (character-for-character) dengan Redirect URI didaftar di
// developer.easyparcel.com DAN yang dihantar semasa mula authorize (pengurusan.html).
// Dikodkan tetap di sini (bukan dari req.url) sebab platform serverless kadang
// tunjuk URL routing dalaman, bukan URL awam sebenar yang EasyParcel nampak.
const EASYPARCEL_REDIRECT_URI = "https://smepriytkoxkmpvjvvzq.supabase.co/functions/v1/easyparcel-oauth-callback";

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const code = url.searchParams.get("code");
  const errorParam = url.searchParams.get("error");
  console.log("EasyParcel callback dipanggil. Full URL:", req.url, "| code hadir:", !!code, "| error param:", errorParam);

  if (errorParam || !code) {
    console.error("EasyParcel redirect tiada code sah — semua query params:", Object.fromEntries(url.searchParams));
    return Response.redirect(REDIRECT_BALIK_GAGAL, 302);
  }

  try {
    const clientId = Deno.env.get("EASYPARCEL_CLIENT_ID")!;
    const clientSecret = Deno.env.get("EASYPARCEL_CLIENT_SECRET")!;
    const basicAuth = btoa(`${clientId}:${clientSecret}`);
    console.log("EasyParcel token exchange — client_id:", clientId, "| redirect_uri dihantar:", EASYPARCEL_REDIRECT_URI, "| client_secret panjang:", clientSecret?.length || 0);

    const tokenRes = await fetch("https://api.easyparcel.com/oauth/token", {
      method: "POST",
      headers: {
        "Authorization": `Basic ${basicAuth}`,
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: new URLSearchParams({
        grant_type: "authorization_code",
        redirect_uri: EASYPARCEL_REDIRECT_URI,
        code,
      }),
    });

    const tokenBodyText = await tokenRes.text();
    console.log("EasyParcel token endpoint status:", tokenRes.status, "body:", tokenBodyText);

    let tokenData;
    try { tokenData = JSON.parse(tokenBodyText); } catch { tokenData = {}; }

    if (!tokenRes.ok || (tokenData.status_code && tokenData.status_code !== 200) || !tokenData.access_token) {
      console.error("EasyParcel token exchange gagal:", tokenBodyText);
      return Response.redirect(REDIRECT_BALIK_GAGAL, 302);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const adminClient = createClient(supabaseUrl, serviceKey);

    const { error: dbErr } = await adminClient.from("easyparcel_auth").update({
      access_token: tokenData.access_token,
      refresh_token: tokenData.refresh_token,
      expires_at: tokenData.expires_at,
      connected_at: new Date().toISOString(),
    }).eq("id", 1);

    if (dbErr) {
      console.error("Gagal simpan token EasyParcel:", dbErr);
      return Response.redirect(REDIRECT_BALIK_GAGAL, 302);
    }

    return Response.redirect(REDIRECT_BALIK_BERJAYA, 302);
  } catch (e) {
    console.error("EasyParcel OAuth callback error:", e);
    return Response.redirect(REDIRECT_BALIK_GAGAL, 302);
  }
});
