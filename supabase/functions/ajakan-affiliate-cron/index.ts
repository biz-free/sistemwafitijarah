// Edge Function: ajakan-affiliate-cron
// Dipanggil SEKALI SEHARI oleh pg_cron (jadual ajakan-affiliate-harian,
// SQL_TAMBAHAN_122) — kempen susulan ajakan Sistem Affiliate kpd pembeli
// lama yg belum jadi affiliate. Sama pola dgn susulan-auto-cron (emel
// pembayaran) — maksimum 3 kali, jarak 3 hari antara setiap emel, berhenti
// automatik bila mereka daftar (padan emel Google mereka) atau cecah had.
//
// Setup wajib: secret RESEND_API_KEY (sedia ada), secret CRON_SECRET (sedia ada).

import { createClient } from "npm:@supabase/supabase-js@2";

const FROM_EMAIL = "Wafi Tijarah Trading <no-reply@wafitijarahtrading.com>";
const HAD_AJAKAN = 3;
const JARAK_HARI = 3;

function esc(s: unknown): string {
  return String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c] as string));
}

async function hantarEmelAjakan(resendKey: string, nama: string, emel: string, kaliKe: number): Promise<boolean> {
  const html = `
    <div style="font-family:Arial,sans-serif;color:#16241D;max-width:480px;margin:0 auto">
      <h2 style="color:#0B3D2E">🎉 Berita Baik — Sistem Affiliate Baharu Wafi Tijarah!</h2>
      <p>Assalamualaikum ${esc(nama || "")},</p>
      <p>Terima kasih sebab pernah membeli dengan Wafi Tijarah Trading.</p>
      <p>Kami baru lancarkan Sistem Affiliate baharu — lebih menguntungkan berbanding kod rujukan lama:</p>
      <p>✅ Setiap kali kawan anda beli guna kod anda, anda dapat <b>komisen 10%</b> — SETIAP pesanan mereka, bukan sekali sahaja<br>
      ✅ Kawan anda pula dapat diskaun terus semasa checkout<br>
      ✅ Dashboard sendiri untuk semak pendapatan & mohon bayaran bila-bila masa</p>
      <p><a href="https://www.wafitijarahtrading.com/affiliate.html" style="background:#0B3D2E;color:#fff;padding:10px 18px;border-radius:8px;text-decoration:none;display:inline-block">Daftar Sekarang (Log Masuk Google)</a></p>
      <p style="font-size:12px;color:#5C7A6C">${kaliKe < HAD_AJAKAN ? `Emel ${kaliKe}/${HAD_AJAKAN} — jika tak berminat, boleh abaikan sahaja emel ini.` : `Ini emel terakhir (${HAD_AJAKAN}/${HAD_AJAKAN}) mengenai tawaran ini.`}</p>
    </div>`;

  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${resendKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({ from: FROM_EMAIL, to: [emel], subject: "🎉 Berita Baik — Sistem Affiliate Baharu Wafi Tijarah!", html }),
  });
  return res.ok;
}

Deno.serve(async (req) => {
  try {
    const cronSecret = Deno.env.get("CRON_SECRET");
    if (cronSecret && req.headers.get("x-cron-secret") !== cronSecret) {
      return new Response(JSON.stringify({ error: "Tidak dibenarkan" }), { status: 401 });
    }

    const resendKey = Deno.env.get("RESEND_API_KEY");
    if (!resendKey) {
      return new Response(JSON.stringify({ error: "RESEND_API_KEY belum ditetapkan sebagai secret" }), { status: 500 });
    }

    const adminClient = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

    // 1. Sync calon baharu — pembeli yang pernah bayar, belum ada dalam senarai ajakan.
    const { data: pembeliList } = await adminClient
      .from("pesanan_edagang")
      .select("pelanggan_email, pelanggan_nama, created_at")
      .eq("status_bayaran", "disahkan")
      .not("pelanggan_email", "is", null)
      .order("created_at", { ascending: false });

    const calonMap = new Map<string, string>();
    for (const p of pembeliList || []) {
      const emel = (p.pelanggan_email || "").trim().toLowerCase();
      if (emel && !calonMap.has(emel)) calonMap.set(emel, p.pelanggan_nama || "");
    }

    let disync = 0;
    for (const [emel, nama] of calonMap) {
      const { error } = await adminClient.from("ajakan_affiliate").insert({ emel, nama });
      if (!error) disync++;
      // Abaikan ralat unique-constraint (emel dah wujud) secara senyap — memang diharapkan.
    }

    // 2. Bina set emel affiliate sedia ada (Google-authenticated).
    const { data: affiliateList } = await adminClient.from("affiliates").select("id");
    const emelAffiliateSet = new Set<string>();
    for (const a of affiliateList || []) {
      const { data: userData } = await adminClient.auth.admin.getUserById(a.id);
      if (userData?.user?.email) emelAffiliateSet.add(userData.user.email.trim().toLowerCase());
    }

    // 3. Tanda "didaftar" utk sesiapa yang emel dah sepadan affiliate sedia ada.
    const { data: menunggu } = await adminClient
      .from("ajakan_affiliate")
      .select("id, emel, nama, bilangan_dihantar, dihantar_terakhir, status")
      .eq("status", "menunggu");

    let didaftar = 0, dihantar = 0, dilangkau = 0, berhenti = 0;
    const jarakMs = JARAK_HARI * 24 * 60 * 60 * 1000;

    for (const row of menunggu || []) {
      if (emelAffiliateSet.has(row.emel)) {
        await adminClient.from("ajakan_affiliate").update({ status: "didaftar" }).eq("id", row.id);
        didaftar++;
        continue;
      }

      if (row.bilangan_dihantar >= HAD_AJAKAN) {
        await adminClient.from("ajakan_affiliate").update({ status: "berhenti" }).eq("id", row.id);
        berhenti++;
        continue;
      }

      const rujukanMasa = row.dihantar_terakhir ? new Date(row.dihantar_terakhir).getTime() : 0;
      const sudahCukupJarak = row.dihantar_terakhir ? (Date.now() - rujukanMasa) >= jarakMs : true;
      if (!sudahCukupJarak) { dilangkau++; continue; }

      const kaliKe = row.bilangan_dihantar + 1;
      const berjaya = await hantarEmelAjakan(resendKey, row.nama, row.emel, kaliKe);
      if (berjaya) {
        await adminClient.from("ajakan_affiliate").update({
          bilangan_dihantar: kaliKe,
          dihantar_terakhir: new Date().toISOString(),
          status: kaliKe >= HAD_AJAKAN ? "berhenti" : "menunggu",
        }).eq("id", row.id);
        dihantar++;
      }
    }

    return new Response(JSON.stringify({ disync, dihantar, didaftar, berhenti, dilangkau, jumlahDiperiksa: (menunggu || []).length }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error("ajakan-affiliate-cron error:", e);
    return new Response(JSON.stringify({ error: String((e as Error)?.message || e) }), { status: 500 });
  }
});
