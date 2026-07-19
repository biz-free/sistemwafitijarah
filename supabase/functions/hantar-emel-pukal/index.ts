// Edge Function: hantar-emel-pukal
// Dipanggil dari pengurusan.html (kad "Data Pembeli" → butang "📧 Emel Pukal")
// untuk hantar SATU emel pemasaran ke SEMUA pelanggan yang ada rekod emel.
// Hanya PEMILIK yang log masuk boleh panggil (disahkan guna token pemanggil +
// jadual profiles, sama seperti reset-pekerja-password). Guna Resend batch API
// (https://resend.com/docs/api-reference/emails/send-batch-emails), maksimum
// 100 emel setiap panggilan API, dengan jeda antara batch untuk elak rate-limit.

import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const FROM_EMAIL = "Wafi Tijarah Trading <no-reply@wafitijarahtrading.com>";
const BATCH_SIZE = 100;

function esc(s: unknown): string {
  return String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c] as string));
}

function personalize(text: string, nama: string): string {
  return nama ? text.split("{nama}").join(nama) : text.split(" {nama}").join("").split("{nama}").join("");
}

function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
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

    const callerClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user }, error: userErr } = await callerClient.auth.getUser();
    if (userErr || !user) {
      return new Response(JSON.stringify({ error: "Token tidak sah" }), { status: 401, headers: corsHeaders });
    }
    const { data: callerProfile } = await callerClient.from("profiles").select("role").eq("id", user.id).single();
    if (callerProfile?.role !== "pemilik") {
      return new Response(JSON.stringify({ error: "Hanya pemilik dibenarkan hantar emel pukal" }), { status: 403, headers: corsHeaders });
    }

    const resendKey = Deno.env.get("RESEND_API_KEY");
    if (!resendKey) {
      return new Response(JSON.stringify({ error: "RESEND_API_KEY belum ditetapkan sebagai secret" }), { status: 500, headers: corsHeaders });
    }

    const { penerima, subjek, mesej } = await req.json();
    if (!Array.isArray(penerima) || !penerima.length) {
      return new Response(JSON.stringify({ error: "Tiada penerima" }), { status: 400, headers: corsHeaders });
    }
    if (!subjek || !mesej) {
      return new Response(JSON.stringify({ error: "Subjek dan mesej diperlukan" }), { status: 400, headers: corsHeaders });
    }

    const validPenerima = penerima.filter((p: { email?: string }) => p && typeof p.email === "string" && p.email.includes("@"));
    if (!validPenerima.length) {
      return new Response(JSON.stringify({ error: "Tiada alamat emel sah dalam senarai penerima" }), { status: 400, headers: corsHeaders });
    }

    let dihantar = 0;
    const gagal: string[] = [];

    for (let i = 0; i < validPenerima.length; i += BATCH_SIZE) {
      const batch = validPenerima.slice(i, i + BATCH_SIZE);
      const payload = batch.map((p: { email: string; nama?: string }) => ({
        from: FROM_EMAIL,
        to: [p.email],
        subject: personalize(subjek, p.nama || ""),
        html: `<div style="font-family:Arial,sans-serif;color:#16241D;max-width:480px;margin:0 auto">${personalize(esc(mesej), esc(p.nama || "")).replace(/\n/g, "<br>")}</div>`,
      }));

      const resendRes = await fetch("https://api.resend.com/emails/batch", {
        method: "POST",
        headers: { "Authorization": `Bearer ${resendKey}`, "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });
      const resendBody = await resendRes.text();
      console.log("Resend batch status:", resendRes.status, "body:", resendBody);

      if (resendRes.ok) {
        dihantar += batch.length;
      } else {
        batch.forEach((p: { email: string }) => gagal.push(p.email));
      }

      if (i + BATCH_SIZE < validPenerima.length) await sleep(600);
    }

    return new Response(JSON.stringify({ dihantar, gagal, jumlah: validPenerima.length }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e?.message || e) }), { status: 500, headers: corsHeaders });
  }
});
