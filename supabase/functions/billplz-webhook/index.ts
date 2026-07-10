// Edge Function: billplz-webhook
// Billplz hantar POST terus ke sini (bukan panggilan dari kod app dengan
// token log masuk) selepas status bayaran berubah — jadi MESTI dideploy
// dengan --no-verify-jwt, sama seperti easyparcel-oauth-callback.
//
// Ini ialah SUMBER KEBENARAN untuk status bayaran — bukan redirect_url
// (query params selepas customer dibawa balik ke laman boleh dipalsukan
// oleh sesiapa dengan lawat URL tu terus). X Signature verification
// memastikan permintaan ini benar-benar dari Billplz.

import { createClient } from "npm:@supabase/supabase-js@2";

async function hmacSha256Hex(key: string, message: string): Promise<string> {
  const enc = new TextEncoder();
  const cryptoKey = await crypto.subtle.importKey(
    "raw", enc.encode(key), { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", cryptoKey, enc.encode(message));
  return Array.from(new Uint8Array(sig)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

// Ikut algoritma rasmi Billplz (disahkan terus dengan test vector dalam
// dokumentasi mereka): susun string GABUNGAN key+value (bukan key sahaja)
// menaik, case-insensitive, gabung dengan "|", HMAC-SHA256.
function bentukSumberTandaTangan(fields: Record<string, string>): string {
  const sumber = Object.entries(fields).map(([k, v]) => `${k}${v ?? ""}`);
  sumber.sort((a, b) => {
    const la = a.toLowerCase(), lb = b.toLowerCase();
    return la < lb ? -1 : la > lb ? 1 : 0;
  });
  return sumber.join("|");
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });

  try {
    let fields: Record<string, string> = {};
    const contentType = req.headers.get("content-type") || "";
    if (contentType.includes("application/json")) {
      const json = await req.json();
      for (const [k, v] of Object.entries(json)) fields[k] = String(v);
    } else {
      const form = await req.formData();
      for (const [k, v] of form.entries()) fields[k] = String(v);
    }

    const xSignatureDiterima = fields["x_signature"];
    delete fields["x_signature"];

    if (!xSignatureDiterima) {
      console.error("Billplz webhook: tiada x_signature dalam permintaan");
      return new Response("Missing signature", { status: 401 });
    }

    const xSignatureKey = Deno.env.get("BILLPLZ_X_SIGNATURE_KEY")!;
    const sumberString = bentukSumberTandaTangan(fields);
    const xSignatureKira = await hmacSha256Hex(xSignatureKey, sumberString);

    if (xSignatureKira !== xSignatureDiterima) {
      console.error("Billplz webhook: x_signature TIDAK PADAN — permintaan mungkin palsu. bill_id:", fields["id"]);
      return new Response("Invalid signature", { status: 401 });
    }

    console.log("Billplz webhook disahkan. bill_id:", fields["id"], "paid:", fields["paid"], "state:", fields["state"]);

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const adminClient = createClient(supabaseUrl, serviceKey);

    const { data: order } = await adminClient.from("pesanan_edagang").select("id, status_bayaran").eq("billplz_bill_id", fields["id"]).single();
    if (!order) {
      console.error("Billplz webhook: tiada pesanan sepadan dengan bill_id", fields["id"]);
      return new Response("OK", { status: 200 }); // tiada apa nak retry — bukan ralat pihak kita
    }

    const dibayar = fields["paid"] === "true";
    const { error: updErr } = await adminClient.from("pesanan_edagang").update({
      status_bayaran: dibayar ? "disahkan" : "gagal",
      updated_at: new Date().toISOString(),
    }).eq("id", order.id);

    if (updErr) {
      console.error("Billplz webhook: gagal kemaskini pesanan", updErr);
      return new Response("Database error", { status: 500 }); // Billplz akan retry
    }

    return new Response("OK", { status: 200 });
  } catch (e) {
    console.error("billplz-webhook error:", e);
    return new Response("Internal error", { status: 500 });
  }
});
