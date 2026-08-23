// Edge Function: notifikasi-invois-lewat-cron
// Dipanggil SEKALI SEHARI oleh pg_cron (bukan dari pengurusan.html) — semak semua
// invois (transaksi status='hutang') yang sudah MELEPASI tarikh_akhir_bayaran &
// belum pernah dimaklumkan, hantar EMEL (Resend) DAN NOTIFIKASI TOLAK (Web Push)
// kepada PEKERJA yang buat penghantaran itu DAN PEMILIK — satu emel/push ringkasan
// setiap penerima (bukan satu per invois, elak spam bila ada byk invois lewat serentak).
//
// Dihantar SEKALI sahaja per invois (medan notifikasi_lewat_dihantar jadi
// penanda) — bukan diulang setiap hari selagi belum bayar, elak keletihan emel/push.
//
// Setup wajib: secret RESEND_API_KEY & CRON_SECRET (sama seperti susulan-auto-cron).
// Push (SQL_TAMBAHAN_110): secret VAPID_PRIVATE_KEY — jika tiada, push dilangkau
// senyap (emel tetap berjalan spt biasa, push cuma ciri tambahan).

import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const FROM_EMAIL = "Wafi Tijarah Trading <no-reply@wafitijarahtrading.com>";
// Kunci AWAM sahaja (padan dgn VAPID_PUBLIC_KEY di pengurusan.html) — selamat
// didedahkan dlm kod, bukan rahsia. Kunci PERIBADI dibaca drpd secret di bawah.
const VAPID_PUBLIC_KEY = "BHn9H44ym7-erXGNS-netsYpsVNke8--awcoLbfcughKJHwb54aOEciUEbYDBidGYdGWDkJtBneOVkz3TDXPqDA";

function esc(s: unknown): string {
  return String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c] as string));
}

function fmt(n: number): string {
  return `RM${Number(n || 0).toFixed(2)}`;
}

interface InvoisLewat {
  id: string;
  resit: string | null;
  jumlah: number;
  tarikh_akhir_bayaran: string;
  created_by: string | null;
  kedai_nama: string;
}

function senaraiHtml(invois: InvoisLewat[]): string {
  return invois.map((t) => {
    const hariLewat = Math.floor((Date.now() - new Date(t.tarikh_akhir_bayaran + "T00:00:00+08:00").getTime()) / 86400000);
    return `<li><b>${esc(t.kedai_nama)}</b> — No. ${esc(t.resit || t.id)} — ${fmt(t.jumlah)} — due ${esc(t.tarikh_akhir_bayaran)} (<span style="color:#C0392B">${hariLewat} hari lewat</span>)</li>`;
  }).join("");
}

async function hantarEmel(resendKey: string, to: string, tajukPenerima: string, invois: InvoisLewat[]): Promise<boolean> {
  const html = `
    <div style="font-family:Arial,sans-serif;color:#16241D;max-width:520px;margin:0 auto">
      <h2 style="color:#0B3D2E">Wafi Tijarah Trading</h2>
      <p>Salam ${esc(tajukPenerima)},</p>
      <p>${invois.length} invois berikut telah <b>melepasi tarikh akhir bayaran</b> dan masih belum dijelaskan:</p>
      <ul style="line-height:1.8">${senaraiHtml(invois)}</ul>
      <p>Sila susulan dengan kedai berkaitan secepat mungkin.</p>
      <p style="font-size:12px;color:#5C7A6C">Emel automatik ini dihantar sekali sahaja bagi setiap invois lewat — sila semak sistem Wafi Tijarah Trading untuk status terkini.</p>
    </div>`;

  const resendRes = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { "Authorization": `Bearer ${resendKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      from: FROM_EMAIL,
      to: [to],
      subject: `⚠️ ${invois.length} Invois Lewat Bayar — Wafi Tijarah Trading`,
      html,
    }),
  });
  const body = await resendRes.text();
  console.log(`[notifikasi-invois-lewat] to=${to} status=${resendRes.status} body=${body}`);
  return resendRes.ok;
}

// deno-lint-ignore no-explicit-any
async function hantarPushKePengguna(admin: any, userId: string, invois: InvoisLewat[]): Promise<number> {
  const { data: subs } = await admin.from("push_subscriptions").select("*").eq("user_id", userId);
  if (!subs || !subs.length) return 0;

  const payload = JSON.stringify({
    title: `⚠️ ${invois.length} Invois Lewat Bayar`,
    body: invois.length === 1
      ? `${invois[0].kedai_nama} — No. ${invois[0].resit || invois[0].id} — ${fmt(invois[0].jumlah)}`
      : `${invois.map((t) => t.kedai_nama).slice(0, 3).join(", ")}${invois.length > 3 ? " & lain-lain" : ""} — jumlah ${fmt(invois.reduce((a, t) => a + t.jumlah, 0))}`,
    url: "./pengurusan.html",
  });

  let berjaya = 0;
  // deno-lint-ignore no-explicit-any
  for (const s of subs as any[]) {
    try {
      await webpush.sendNotification({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth_key } }, payload);
      berjaya++;
    } catch (err) {
      const kod = (err as { statusCode?: number })?.statusCode;
      console.warn(`[notifikasi-invois-lewat] push gagal endpoint=${s.endpoint} kod=${kod} err=${err}`);
      // 404/410 = langganan dah tak sah (peranti nyahpasang/tukar) — buang drpd DB.
      if (kod === 404 || kod === 410) await admin.from("push_subscriptions").delete().eq("id", s.id);
    }
  }
  return berjaya;
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

    // Push ialah ciri TAMBAHAN kpd emel — jika VAPID_PRIVATE_KEY belum ditetapkan,
    // langkau push senyap (emel tetap berjalan spt biasa, tak gagalkan seluruh fungsi).
    const vapidPrivateKey = Deno.env.get("VAPID_PRIVATE_KEY");
    const pushAktif = !!vapidPrivateKey;
    if (pushAktif) {
      webpush.setVapidDetails("mailto:wafitijarahtrading@gmail.com", VAPID_PUBLIC_KEY, vapidPrivateKey!);
    }

    const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

    const hariIniMY = new Date(Date.now() + 8 * 60 * 60 * 1000).toISOString().slice(0, 10);

    const { data: trxList, error: qErr } = await admin
      .from("transaksi")
      .select("id, resit, jumlah, tarikh_akhir_bayaran, created_by, kedai_id")
      .eq("status", "hutang")
      .eq("notifikasi_lewat_dihantar", false)
      .not("tarikh_akhir_bayaran", "is", null)
      .lt("tarikh_akhir_bayaran", hariIniMY);

    if (qErr) return new Response(JSON.stringify({ error: qErr.message }), { status: 500 });
    if (!trxList || !trxList.length) {
      return new Response(JSON.stringify({ mesej: "Tiada invois lewat baharu", jumlah: 0 }), { status: 200 });
    }

    const kedaiIds = [...new Set(trxList.map((t) => t.kedai_id).filter(Boolean))];
    const { data: kedaiList } = await admin.from("kedai").select("id, nama").in("id", kedaiIds);
    const namaKedai = new Map((kedaiList || []).map((k) => [k.id, k.nama]));

    const invoisLewat: InvoisLewat[] = trxList.map((t) => ({
      id: t.id,
      resit: t.resit,
      jumlah: t.jumlah,
      tarikh_akhir_bayaran: t.tarikh_akhir_bayaran,
      created_by: t.created_by,
      kedai_nama: t.kedai_id ? (namaKedai.get(t.kedai_id) || t.kedai_id) : "Belian Peribadi",
    }));

    // Kumpul ikut pekerja (created_by) — satu emel ringkasan setiap pekerja.
    const ikutPekerja = new Map<string, InvoisLewat[]>();
    invoisLewat.forEach((t) => {
      if (!t.created_by) return;
      if (!ikutPekerja.has(t.created_by)) ikutPekerja.set(t.created_by, []);
      ikutPekerja.get(t.created_by)!.push(t);
    });

    const pekerjaIds = [...ikutPekerja.keys()];
    const { data: profilPekerja } = pekerjaIds.length
      ? await admin.from("profiles").select("id, nama, email").in("id", pekerjaIds)
      : { data: [] as { id: string; nama: string; email: string | null }[] };
    const { data: profilPemilik } = await admin.from("profiles").select("id, nama, email").eq("role", "pemilik");

    let dihantarPekerja = 0, dihantarPemilik = 0, pushDihantar = 0;

    for (const [pid, senarai] of ikutPekerja) {
      const p = (profilPekerja || []).find((x) => x.id === pid);
      if (p?.email) {
        const ok = await hantarEmel(resendKey, p.email, p.nama || "Pekerja", senarai);
        if (ok) dihantarPekerja++;
      }
      if (pushAktif) pushDihantar += await hantarPushKePengguna(admin, pid, senarai);
    }

    for (const p of profilPemilik || []) {
      if (p.email) {
        const ok = await hantarEmel(resendKey, p.email, p.nama || "Pemilik", invoisLewat);
        if (ok) dihantarPemilik++;
      }
      if (pushAktif) pushDihantar += await hantarPushKePengguna(admin, p.id, invoisLewat);
    }

    // Tanda SEMUA invois yg diproses pusingan ni sbg sudah dimaklumkan — sekali
    // sahaja per invois, tak diulang setiap hari selagi belum bayar.
    await admin.from("transaksi").update({ notifikasi_lewat_dihantar: true }).in("id", invoisLewat.map((t) => t.id));

    return new Response(JSON.stringify({
      jumlahInvois: invoisLewat.length,
      pekerjaDimaklumkan: dihantarPekerja,
      pemilikDimaklumkan: dihantarPemilik,
      pushDihantar,
      pushAktif,
    }), { status: 200, headers: { "Content-Type": "application/json" } });
  } catch (e) {
    console.error("notifikasi-invois-lewat-cron error:", e);
    return new Response(JSON.stringify({ error: String((e as Error)?.message || e) }), { status: 500 });
  }
});
