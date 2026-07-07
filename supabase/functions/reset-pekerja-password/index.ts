// Edge Function: reset-pekerja-password
// Hanya PEMILIK yang log masuk boleh panggil fungsi ini untuk tetapkan semula
// kata laluan seorang pekerja kepada "admin123". Guna service_role key
// (tersedia automatik sebagai env var dalam Edge Function — TIDAK PERNAH
// terdedah kepada client) supaya operasi admin ini selamat.

import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

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

    // Client guna token PEMANGGIL — untuk sahkan siapa dia sebenarnya
    const callerClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user }, error: userErr } = await callerClient.auth.getUser();
    if (userErr || !user) {
      return new Response(JSON.stringify({ error: "Token tidak sah" }), { status: 401, headers: corsHeaders });
    }

    const { data: callerProfile } = await callerClient.from("profiles").select("role").eq("id", user.id).single();
    if (callerProfile?.role !== "pemilik") {
      return new Response(JSON.stringify({ error: "Hanya pemilik dibenarkan reset kata laluan pekerja" }), { status: 403, headers: corsHeaders });
    }

    const { targetUserId } = await req.json();
    if (!targetUserId) {
      return new Response(JSON.stringify({ error: "targetUserId diperlukan" }), { status: 400, headers: corsHeaders });
    }

    // Client admin (service_role) — HANYA dalam Edge Function, tak pernah ke client
    const adminClient = createClient(supabaseUrl, serviceKey);
    const { error: updErr } = await adminClient.auth.admin.updateUserById(targetUserId, { password: "admin123" });
    if (updErr) {
      return new Response(JSON.stringify({ error: updErr.message }), { status: 500, headers: corsHeaders });
    }

    await adminClient.from("profiles").update({ must_change_password: true }).eq("id", targetUserId);

    return new Response(JSON.stringify({ success: true }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: corsHeaders });
  }
});
