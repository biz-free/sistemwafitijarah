// Edge Function: easyparcel-wallet-balance
// Dipanggil oleh staff dari Profile > EasyParcel untuk papar baki wallet
// semasa (supaya nampak awal-awal sebelum cuba jana label & gagal sebab
// baki tak cukup). client_secret & access_token EasyParcel kekal di server.

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
      return new Response(JSON.stringify({ error: "Hanya staff dibenarkan semak baki EasyParcel" }), { status: 403, headers: corsHeaders });
    }

    const adminClient = createClient(supabaseUrl, serviceKey);
    const accessToken = await ambilTokenSah(adminClient);

    const walletRes = await fetch("https://api.easyparcel.com/open_api/2026-06/wallet", {
      headers: { "Authorization": `Bearer ${accessToken}` },
    });
    const walletBodyText = await walletRes.text();
    let walletData: any = {};
    try { walletData = JSON.parse(walletBodyText); } catch { /* biar kosong */ }

    if (!walletRes.ok || walletData?.status_code !== 200) {
      return new Response(JSON.stringify({ error: "Gagal semak baki EasyParcel", detail: walletBodyText }), { status: 502, headers: corsHeaders });
    }

    const wallet = walletData?.data?.wallet?.[0] || { balance: 0, currency: "MYR" };
    const freeCredit = walletData?.data?.free_credit_wallet?.[0] || { balance: 0, currency: "MYR" };

    return new Response(JSON.stringify({ balance: wallet.balance, currency: wallet.currency, free_credit: freeCredit.balance }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error("easyparcel-wallet-balance error:", e);
    return new Response(JSON.stringify({ error: String(e?.message || e) }), { status: 500, headers: corsHeaders });
  }
});
