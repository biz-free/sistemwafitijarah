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

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const code = url.searchParams.get("code");
  const errorParam = url.searchParams.get("error");

  if (errorParam || !code) {
    return Response.redirect(REDIRECT_BALIK_GAGAL, 302);
  }

  try {
    const clientId = Deno.env.get("EASYPARCEL_CLIENT_ID")!;
    const clientSecret = Deno.env.get("EASYPARCEL_CLIENT_SECRET")!;
    // redirect_uri dihantar semula MESTI sama persis dengan yang didaftar/digunakan
    // semasa mula authorize — guna origin+pathname permintaan semasa (URL Edge Function ini sendiri).
    const redirectUri = `${url.origin}${url.pathname}`;
    const basicAuth = btoa(`${clientId}:${clientSecret}`);

    const tokenRes = await fetch("https://api.easyparcel.com/oauth/token", {
      method: "POST",
      headers: {
        "Authorization": `Basic ${basicAuth}`,
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: new URLSearchParams({
        grant_type: "authorization_code",
        redirect_uri: redirectUri,
        code,
      }),
    });

    if (!tokenRes.ok) {
      console.error("EasyParcel token exchange failed:", await tokenRes.text());
      return Response.redirect(REDIRECT_BALIK_GAGAL, 302);
    }

    const tokenData = await tokenRes.json();

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
