// Edge Function: mypa-mohon-padam
// Pintu MASUK TERHAD untuk VPS myPA: myPA hanya boleh HANTAR permohonan padam
// (jenis 'kedai' atau 'transaksi'). Ia TIDAK boleh lulus, tolak atau padam apa-apa —
// permohonan masuk jadual permohonan_padam (status 'menunggu') dan trigger sedia ada
// (trg_notify_pemilik_padam) hantar kad Telegram Lulus/Tolak kepada pemilik. Pemilik
// sahaja yang memutuskan (telegram_putuskan_padam, SQL_TAMBAHAN_165).
//
// Pengesahan: header "x-mypa-key" mesti sama dengan secret MYPA_API_KEY (tetapkan di
// Supabase > Edge Functions > Secrets). Jika secret belum ditetapkan, fungsi MENOLAK semua
// permintaan (fail-closed).
// Deploy: npx supabase functions deploy mypa-mohon-padam --no-verify-jwt
//
// POST { "jenis": "kedai" | "transaksi", "rekod_id": "K1420066", "sebab": "..." }

import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "x-mypa-key, content-type",
};
const MAKS_MENUNGGU = 20; // had permohonan myPA yang belum diputuskan (elak banjir kad Telegram)

const json = (o: unknown, status = 200) =>
  new Response(JSON.stringify(o), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });

function samaSelamat(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let r = 0;
  for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return r === 0;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Gunakan POST" }, 405);

  try {
    const kunci = Deno.env.get("MYPA_API_KEY");
    if (!kunci) return json({ error: "MYPA_API_KEY belum ditetapkan di server" }, 503);
    const diterima = req.headers.get("x-mypa-key") || "";
    if (!samaSelamat(diterima, kunci)) return json({ error: "Kunci tidak sah" }, 401);

    const { jenis, rekod_id, sebab } = await req.json();
    if (!["kedai", "transaksi"].includes(jenis)) return json({ error: "jenis mesti 'kedai' atau 'transaksi'" }, 400);
    if (!rekod_id || typeof rekod_id !== "string" || rekod_id.length > 64) return json({ error: "rekod_id diperlukan" }, 400);
    const sebabBersih = String(sebab ?? "").trim().slice(0, 300);

    const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

    // Rekod mesti wujud — dan ambil label untuk kad Telegram
    let label: string | null = null;
    if (jenis === "kedai") {
      const { data } = await admin.from("kedai").select("id, nama").eq("id", rekod_id).maybeSingle();
      if (!data) return json({ error: "Kedai tidak dijumpai" }, 404);
      label = data.nama;
    } else {
      const { data } = await admin.from("transaksi").select("id, resit").eq("id", rekod_id).maybeSingle();
      if (!data) return json({ error: "Transaksi tidak dijumpai" }, 404);
      label = data.resit || data.id;
    }

    // Elak permohonan berganda untuk rekod yang sama
    const { data: sedia } = await admin.from("permohonan_padam").select("id")
      .eq("jenis", jenis).eq("rekod_id", rekod_id).eq("status", "menunggu").limit(1);
    if (sedia?.length) return json({ ok: true, ulang: true, id: sedia[0].id, mesej: "Sudah ada permohonan menunggu untuk rekod ini" });

    const { count } = await admin.from("permohonan_padam").select("id", { count: "exact", head: true })
      .eq("status", "menunggu").like("sebab", "[myPA]%");
    if ((count ?? 0) >= MAKS_MENUNGGU) return json({ error: `Terlalu banyak permohonan myPA belum diputuskan (had ${MAKS_MENUNGGU})` }, 429);

    const id = "PP" + Math.floor(1000000 + Math.random() * 9000000);
    const { error } = await admin.from("permohonan_padam").insert({
      id, jenis, rekod_id, rekod_label: label,
      sebab: `[myPA] ${sebabBersih || "tiada sebab diberi"}`,
      pekerja_id: null, status: "menunggu",
    });
    if (error) return json({ error: "Gagal simpan permohonan: " + error.message }, 500);

    console.log("mypa-mohon-padam", id, jenis, rekod_id);
    return json({ ok: true, id, mesej: "Permohonan dihantar — menunggu pemilik lulus di Telegram" });
  } catch (e) {
    return json({ error: String((e as Error)?.message || e) }, 500);
  }
});
