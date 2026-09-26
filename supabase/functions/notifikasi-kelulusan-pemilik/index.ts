// Edge Function: notifikasi-kelulusan-pemilik
// Dipanggil oleh trigger pg_net (notify_pemilik_kelulusan, SQL_TAMBAHAN_65) bila
// ada permohonan BAHARU perlu kelulusan pemilik: permohonan_padam, permohonan_cuti,
// serahan_cash, serahan_produk (reject/ambil) — elak pekerja tunggu lama tanpa
// pemilik sedar ada permohonan menunggu. Guna Resend, sama corak dgn
// hantar-emel-susulan (RESEND_API_KEY secret sedia ada, domain wafitijarahtrading.com
// sudah disahkan).
//
// Push (susulan SQL_TAMBAHAN_110 — Notifikasi Tolak): hantar push SELARI dgn emel
// (bukan ganti) kpd setiap pemilik yg sudah langgan. Jika VAPID_PRIVATE_KEY belum
// ditetapkan, push dilangkau senyap — emel tetap berjalan spt biasa.
//
// Turut dipanggil oleh trg_notify_pemilik_pesanan_baru (SQL_TAMBAHAN_118) bila
// pelanggan buat tempahan e-dagang baharu (index.html/pesan.html) — jenis
// 'Tempahan E-Dagang Baharu' guna label "Pelanggan" & wording jualan, bukan
// "perlu kelulusan" (order bukan permohonan pekerja).
//
// Turut dipanggil oleh trg_notify_pemilik_preorder_baru (SQL_TAMBAHAN_119) bila
// kedai buat tempahan pre-order baharu (pesan.html) — jenis 'Pre-Order Baharu'
// guna label "Kedai".
//
// Telegram (susulan SQL_TAMBAHAN_146): hantar mesej Telegram SELARI dgn emel+push
// (TAMBAHAN, bukan ganti) kpd setiap chat_id berdaftar dlm telegram_admin yg aktif
// & notifikasi_aktif=true. Jika record_id/jenis_rekod disertakan dlm payload (drpd
// notify_pemilik_kelulusan(), utk 4 jadual yg disokong tindakan Telegram — lihat
// SQL_TAMBAHAN_146), mesej turut disertakan butang ✅ Lulus / ✕ Tolak. Jika
// TELEGRAM_BOT_TOKEN belum ditetapkan sbg secret, Telegram dilangkau senyap —
// emel+push tetap berjalan spt biasa.
//
// saluran="telegram_sahaja" (susulan SQL_TAMBAHAN_148, notifikasi Thumb In):
// sesetengah notifikasi (cth. rutin 2x sehari setiap pekerja) tak sesuai
// bebankan emel+push pemilik — bila payload sertakan "saluran":"telegram_sahaja",
// fungsi ni LANGSUNG hantar Telegram sahaja & pulang awal, tanpa perlukan
// RESEND_API_KEY/pemilik emel langsung.

import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

// jadual disokong utk butang Lulus/Tolak Telegram — mesti PADAN dgn CODE_JADUAL
// dlm supabase/functions/telegram-webhook/index.ts (jangan ubah salah satu tanpa
// yang lain).
const JADUAL_CODE: Record<string, string> = {
  serahan_cash: "sc",
  permohonan_cuti: "cu",
  permohonan_bayaran_hutang: "bh",
  serahan_produk: "sp",
  baucar_bayaran: "bu",
  transaksi: "tf",
  permohonan_padam: "pd", // SQL_TAMBAHAN_154: butang hanya utk padam jenis transaksi (butiran bermula "Transaksi ")
};

// deno-lint-ignore no-explicit-any
async function hantarTelegram(admin: any, jenis: string, pekerjaNama: string, butiran: string, recordId?: string, jenisRekod?: string): Promise<number> {
  const token = Deno.env.get("TELEGRAM_BOT_TOKEN");
  if (!token) return 0;
  const { data: adminList } = await admin.from("telegram_admin").select("chat_id").eq("aktif", true).eq("notifikasi_aktif", true);
  if (!adminList?.length) return 0;

  const text = `🔔 ${jenis}\n👤 ${pekerjaNama}\n${butiran || ""}`.trim();
  let replyMarkup: unknown = undefined;
  const padamBukanTransaksi = jenisRekod === "permohonan_padam" && !String(butiran || "").startsWith("Transaksi ");
  if (recordId && jenisRekod && JADUAL_CODE[jenisRekod] && !padamBukanTransaksi) {
    const code = JADUAL_CODE[jenisRekod];
    // baucar_bayaran guna status draf/diluluskan/dibatalkan (bukan menunggu/disahkan/
    // ditolak spt 4 jadual lain) — label butang "Batal" lebih tepat drpd "Tolak".
    const labelTolak = jenisRekod === "baucar_bayaran" ? "✕ Batal" : jenisRekod === "transaksi" ? "✕ Belum Masuk → Hutang" : "✕ Tolak";
    // transaksi = Online Transfer (SQL_TAMBAHAN_151/152): "Duit Masuk" / "Belum Masuk → Hutang"
    // (Belum Masuk auto tukar transaksi kpd hutang).
    const labelLulus = jenisRekod === "transaksi" ? "✅ Duit Masuk" : jenisRekod === "permohonan_padam" ? "✅ Luluskan & Padam" : "✅ Lulus";
    replyMarkup = { inline_keyboard: [[
      { text: labelLulus, callback_data: `tp:${code}:${recordId}:A` },
      { text: labelTolak, callback_data: `tp:${code}:${recordId}:R` },
    ]] };
  }

  let berjaya = 0;
  // deno-lint-ignore no-explicit-any
  for (const a of adminList as any[]) {
    try {
      const res = await fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ chat_id: a.chat_id, text, reply_markup: replyMarkup }),
      });
      const j = await res.json();
      if (j.ok) berjaya++;
      else console.warn(`[notifikasi-kelulusan-pemilik] telegram gagal chat_id=${a.chat_id}`, j);
    } catch (err) {
      console.warn(`[notifikasi-kelulusan-pemilik] telegram error chat_id=${a.chat_id}`, err);
    }
  }
  return berjaya;
}

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const FROM_EMAIL = "Wafi Tijarah Trading <no-reply@wafitijarahtrading.com>";
// Kunci AWAM sahaja (padan dgn VAPID_PUBLIC_KEY di pengurusan.html) — selamat
// didedahkan, bukan rahsia. Kunci PERIBADI dibaca drpd secret VAPID_PRIVATE_KEY.
const VAPID_PUBLIC_KEY = "BHn9H44ym7-erXGNS-netsYpsVNke8--awcoLbfcughKJHwb54aOEciUEbYDBidGYdGWDkJtBneOVkz3TDXPqDA";

function esc(s: unknown): string {
  return String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c] as string));
}

// deno-lint-ignore no-explicit-any
async function hantarPushKePengguna(admin: any, userId: string, title: string, body: string): Promise<number> {
  const { data: subs } = await admin.from("push_subscriptions").select("*").eq("user_id", userId);
  if (!subs || !subs.length) return 0;
  const payload = JSON.stringify({ title, body, url: "./pengurusan.html" });
  let berjaya = 0;
  // deno-lint-ignore no-explicit-any
  for (const s of subs as any[]) {
    try {
      await webpush.sendNotification({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth_key } }, payload);
      berjaya++;
    } catch (err) {
      const kod = (err as { statusCode?: number })?.statusCode;
      console.warn(`[notifikasi-kelulusan-pemilik] push gagal endpoint=${s.endpoint} kod=${kod} err=${err}`);
      if (kod === 404 || kod === 410) await admin.from("push_subscriptions").delete().eq("id", s.id);
    }
  }
  return berjaya;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const { jenis, pekerja_nama, butiran, record_id, jenis_rekod, saluran } = await req.json();
    if (!jenis) {
      return new Response(JSON.stringify({ error: "jenis diperlukan" }), { status: 400, headers: corsHeaders });
    }

    // saluran="telegram_sahaja" — langkau terus emel+push, Telegram sahaja.
    if (saluran === "telegram_sahaja") {
      const adminClientTG = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
      let telegramSahaja = 0;
      try {
        telegramSahaja = await hantarTelegram(adminClientTG, jenis, pekerja_nama, butiran, record_id, jenis_rekod);
      } catch (err) {
        console.warn("[notifikasi-kelulusan-pemilik] telegram_sahaja gagal:", err);
      }
      return new Response(JSON.stringify({ ok: true, saluran: "telegram_sahaja", telegramDihantar: telegramSahaja }), {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const iaTempahan = jenis === "Tempahan E-Dagang Baharu";
    const iaPreOrder = jenis === "Pre-Order Baharu";
    const iaJualan = iaTempahan || iaPreOrder;
    const labelOrang = iaTempahan ? "Pelanggan" : iaPreOrder ? "Kedai" : "Pekerja";
    const ikonJualan = iaPreOrder ? "📦" : "🛒";
    const headingEmel = iaJualan ? `${ikonJualan} ${jenis}` : "🔔 Permohonan Baharu Perlu Kelulusan";
    const subjekEmel = iaJualan ? `${ikonJualan} ${jenis}` : `🔔 ${jenis} — Perlu Kelulusan`;

    const resendKey = Deno.env.get("RESEND_API_KEY");
    if (!resendKey) {
      return new Response(JSON.stringify({ error: "RESEND_API_KEY belum ditetapkan sebagai secret" }), { status: 500, headers: corsHeaders });
    }

    const vapidPrivateKey = Deno.env.get("VAPID_PRIVATE_KEY");
    const pushAktif = !!vapidPrivateKey;
    if (pushAktif) {
      webpush.setVapidDetails("mailto:wafitijarahtrading@gmail.com", VAPID_PUBLIC_KEY, vapidPrivateKey!);
    }

    const adminClient = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

    const { data: pemilikList, error: pemilikErr } = await adminClient
      .from("profiles")
      .select("id")
      .eq("role", "pemilik");
    if (pemilikErr || !pemilikList?.length) {
      return new Response(JSON.stringify({ error: "Tiada akaun pemilik dijumpai" }), { status: 404, headers: corsHeaders });
    }

    const emails: string[] = [];
    for (const p of pemilikList) {
      const { data: userData } = await adminClient.auth.admin.getUserById(p.id);
      if (userData?.user?.email) emails.push(userData.user.email);
    }
    if (!emails.length) {
      return new Response(JSON.stringify({ error: "Tiada emel pemilik dijumpai" }), { status: 404, headers: corsHeaders });
    }

    const html = `
      <div style="font-family:sans-serif;max-width:480px;margin:0 auto">
        <h2 style="color:#0D2137">${headingEmel}</h2>
        ${iaJualan ? "" : `<p><b>Jenis:</b> ${esc(jenis)}</p>`}
        <p><b>${labelOrang}:</b> ${esc(pekerja_nama)}</p>
        <p><b>Butiran:</b> ${esc(butiran)}</p>
        <p style="margin-top:20px">
          <a href="https://www.wafitijarahtrading.com/pengurusan.html" style="background:#0D2137;color:#fff;padding:10px 20px;border-radius:8px;text-decoration:none">Buka Sistem Pengurusan</a>
        </p>
        <p style="font-size:11px;color:#888;margin-top:24px">Emel automatik — sila jangan balas.</p>
      </div>`;

    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${resendKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        from: FROM_EMAIL,
        to: emails,
        subject: subjekEmel,
        html,
      }),
    });
    const resendResult = await res.json();
    if (!res.ok) {
      return new Response(JSON.stringify({ error: "Resend gagal: " + JSON.stringify(resendResult) }), { status: 502, headers: corsHeaders });
    }

    let pushDihantar = 0;
    if (pushAktif) {
      const pushTitle = subjekEmel;
      const pushBody = `${pekerja_nama || labelOrang}: ${butiran || ""}`.trim();
      for (const p of pemilikList) {
        pushDihantar += await hantarPushKePengguna(adminClient, p.id, pushTitle, pushBody);
      }
    }

    let telegramDihantar = 0;
    try {
      telegramDihantar = await hantarTelegram(adminClient, jenis, pekerja_nama, butiran, record_id, jenis_rekod);
    } catch (err) {
      console.warn("[notifikasi-kelulusan-pemilik] telegram gagal keseluruhan:", err);
    }

    return new Response(JSON.stringify({ ok: true, sent_to: emails.length, pushDihantar, pushAktif, telegramDihantar }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String((e as Error)?.message || e) }), { status: 500, headers: corsHeaders });
  }
});
