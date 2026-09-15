// Edge Function: telegram-webhook
// ═══════════════════════════════════════════════════════════
// Bot Telegram utk pemilik Wafi Tijarah Trading — supaya pemilik boleh
// terima SEMUA notifikasi permohonan pekerja & terus lulus/tolak dari
// Telegram walaupun tak sempat buka Sistem Pengurusan (pengurusan.html).
// Rujuk SQL_TAMBAHAN_146 utk reka bentuk jadual/RPC yang disokong fungsi ni.
//
// KESELAMATAN (PENTING):
//  • TELEGRAM_BOT_TOKEN & TELEGRAM_WEBHOOK_SECRET disimpan sbg Supabase
//    Edge Function SECRETS (Deno.env.get) — TIDAK PERNAH didedahkan kpd
//    klien/browser atau ditulis dlm pengurusan.html.
//  • Setiap permintaan MASUK drpd Telegram disahkan menggunakan header
//    X-Telegram-Bot-Api-Secret-Token (mesti padan TELEGRAM_WEBHOOK_SECRET)
//    — corak rasmi Telegram utk sahkan webhook, spt billplz-webhook.
//  • Tindakan TULIS (lulus/tolak) HANYA berlaku melalui RPC
//    telegram_putuskan() yg mengesahkan chat_id berdaftar & masih aktif
//    & terikat kpd akaun role='pemilik' SEBELUM apa2 perubahan — fungsi
//    itu sendiri dikunci kpd service_role sahaja di peringkat DB (lihat
//    SQL_TAMBAHAN_146), jadi walaupun webhook ni "diteka" URL-nya,
//    sesiapa yg BUKAN admin Telegram berdaftar tak boleh buat apa2.
//  • Pautan (/link) perlukan KOD sekali-guna 15-minit yg pemilik jana
//    sendiri drpd dalam Sistem Pengurusan (RPC jana_kod_pautan_telegram)
//    — bukan sesiapa boleh daftar diri sbg admin Telegram.
//  • Aksi "?setup=1" (daftar webhook dgn Telegram, sekali sahaja lepas
//    secrets ditetapkan) dikunci di belakang header X-Setup-Key yg mesti
//    padan TELEGRAM_WEBHOOK_SECRET jugak — bukan endpoint awam.
//  • Aksi "?cron=laporan" (SQL_TAMBAHAN_148 — laporan harian automatik
//    pukul 8 pagi via pg_cron) dikunci dgn header x-cron-key yg mesti
//    padan secret BERASINGAN CRON_LAPORAN_SECRET — sengaja bukan
//    TELEGRAM_WEBHOOK_SECRET yg sama, supaya dua laluan admin ni tak
//    berkongsi kunci.

import { createClient } from "npm:@supabase/supabase-js@2";

const BOT_TOKEN = Deno.env.get("TELEGRAM_BOT_TOKEN") || "";
const WEBHOOK_SECRET = Deno.env.get("TELEGRAM_WEBHOOK_SECRET") || "";
// Secret BAHARU (SQL_TAMBAHAN_148) — berasingan drpd TELEGRAM_WEBHOOK_SECRET,
// khusus mengesahkan panggilan pg_cron (?cron=laporan) drpd Postgres, supaya
// endpoint setup webhook & endpoint cron tak berkongsi kunci yg sama.
const CRON_KEY = Deno.env.get("CRON_LAPORAN_SECRET") || "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const TG_API = `https://api.telegram.org/bot${BOT_TOKEN}`;

const sb = createClient(SUPABASE_URL, SERVICE_KEY);

// jadual disokong utk butang Lulus/Tolak — kod pendek utk jimat byte dlm callback_data
const CODE_JADUAL: Record<string, string> = {
  sc: "serahan_cash",
  cu: "permohonan_cuti",
  bh: "permohonan_bayaran_hutang",
  sp: "serahan_produk",
  bu: "baucar_bayaran",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
function fmtRM(n: unknown): string {
  const v = Number(n) || 0;
  return "RM" + v.toFixed(2);
}
function tarikhKL(d?: string | Date | null): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Kuala_Lumpur", year: "numeric", month: "2-digit", day: "2-digit" })
    .format(d ? (d instanceof Date ? d : new Date(d)) : new Date());
}
function fmtD(dateStr?: string | null): string {
  if (!dateStr) return "-";
  const [y, m, d] = String(dateStr).slice(0, 10).split("-");
  return d && m && y ? `${d}/${m}/${y}` : dateStr;
}
function nowKLDisplay(): string {
  return new Intl.DateTimeFormat("ms-MY", { timeZone: "Asia/Kuala_Lumpur", dateStyle: "short", timeStyle: "short" }).format(new Date());
}
// "Semalam" ikut kalendar waktu Malaysia — tolak tepat 24j drpd waktu sebenar
// (Malaysia UTC+8 sepanjang tahun, tiada DST, jadi ini SENTIASA betul walau
// apa pun jam semasa di Malaysia).
function tarikhSemalamKL(): string {
  return tarikhKL(new Date(Date.now() - 24 * 3600 * 1000));
}
function fmtJam(dateStr?: string | null): string {
  if (!dateStr) return "-";
  return new Intl.DateTimeFormat("en-GB", { timeZone: "Asia/Kuala_Lumpur", hour: "2-digit", minute: "2-digit", hour12: false }).format(new Date(dateStr));
}
function fmtDurasi(mulaISO: string, akhirISO?: string | null): string {
  if (!akhirISO) return "sedang bekerja ⏳";
  const minit = Math.round((new Date(akhirISO).getTime() - new Date(mulaISO).getTime()) / 60000);
  const jam = Math.floor(minit / 60);
  const baki = minit % 60;
  return `${jam}j ${baki}m`;
}

async function tg(method: string, payload: Record<string, unknown>) {
  const res = await fetch(`${TG_API}/${method}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  return res.json();
}
function sendMessage(chatId: number, text: string, replyMarkup?: unknown) {
  return tg("sendMessage", { chat_id: chatId, text, reply_markup: replyMarkup, disable_web_page_preview: true });
}
function answerCallback(id: string, text?: string, showAlert = false) {
  return tg("answerCallbackQuery", { callback_query_id: id, text, show_alert: showAlert });
}
function editText(chatId: number, messageId: number, text: string) {
  return tg("editMessageText", { chat_id: chatId, message_id: messageId, text });
}
function kb(code: string, id: string) {
  return { inline_keyboard: [[{ text: "✅ Lulus", callback_data: `tp:${code}:${id}:A` }, { text: "✕ Tolak", callback_data: `tp:${code}:${id}:R` }]] };
}
// baucar_bayaran guna status draf/diluluskan/dibatalkan — label "Batal" lebih tepat.
function kbBaucar(id: string) {
  return { inline_keyboard: [[{ text: "✅ Lulus", callback_data: `tp:bu:${id}:A` }, { text: "✕ Batal", callback_data: `tp:bu:${id}:R` }]] };
}

// ── SQL_TAMBAHAN_148: butang "🔙 Menu" pada SETIAP paparan supaya pemilik
// senang kembali ke menu utama tanpa perlu taip arahan semula. ──
const MENU_BTN = { text: "🔙 Menu", callback_data: "mnu:menu" };
function withMenu(keyboard?: { inline_keyboard: unknown[][] }) {
  if (!keyboard) return { inline_keyboard: [[MENU_BTN]] };
  return { inline_keyboard: [...keyboard.inline_keyboard, [MENU_BTN]] };
}
function cmdMenu(chatId: number) {
  const kb2 = {
    inline_keyboard: [
      [{ text: "📊 Status", callback_data: "mnu:status" }, { text: "💰 Cash", callback_data: "mnu:cash" }],
      [{ text: "🔔 Menunggu", callback_data: "mnu:menunggu" }, { text: "🧾 Baucar", callback_data: "mnu:baucar" }],
      [{ text: "📋 Hutang", callback_data: "mnu:hutang" }, { text: "📦 Stok", callback_data: "mnu:stok" }],
      [{ text: "🛒 Jualan", callback_data: "mnu:jualan" }, { text: "👥 Pekerja", callback_data: "mnu:pekerja" }],
      [{ text: "💳 Transfer", callback_data: "mnu:transfer" }, { text: "🗑️ Padam", callback_data: "mnu:padam" }],
      [{ text: "📰 Laporan Harian", callback_data: "mnu:laporan" }],
      [{ text: "❓ Bantuan", callback_data: "mnu:help" }],
    ],
  };
  return sendMessage(chatId, "📋 Menu Utama — pilih arahan:", kb2);
}

async function getAdmin(chatId: number): Promise<{ user_id: string; nama: string } | null> {
  const { data } = await sb.from("telegram_admin").select("user_id,nama").eq("chat_id", chatId).eq("aktif", true).maybeSingle();
  return data ? { user_id: data.user_id, nama: data.nama || "Pemilik" } : null;
}

// ── /cash — replika TEPAT logik kiraCashDipegang()/jumlahCashBelumDiselesai()
// drpd pengurusan.html (bahagian "URUS PEKERJA" / dashboard "Cash Dipegang")
// supaya nombor SENTIASA konsisten dgn apa yg pemilik nampak dlm sistem. ──
async function kiraCashSemuaPekerja() {
  const [{ data: transaksiTunai }, { data: baucarHarian }, { data: hutangTunai }, { data: serahanCash }, { data: profiles }] = await Promise.all([
    sb.from("transaksi").select("created_by,jumlah,tarikh_masa").eq("kaedah_bayaran", "tunai").eq("status", "selesai"),
    sb.from("baucar_bayaran").select("pekerja_id,tarikh,jumlah").eq("kategori", "upah_harian").neq("status", "dibatalkan"),
    sb.from("permohonan_bayaran_hutang").select("pekerja_id,jumlah,created_at").eq("kaedah_bayaran", "tunai").eq("status", "disahkan"),
    sb.from("serahan_cash").select("pekerja_id,jumlah,status"),
    sb.from("profiles").select("id,nama").eq("role", "pekerja"),
  ]);
  const namaOf = (id: string) => profiles?.find((p: any) => p.id === id)?.nama || id;

  const pekerjaIds = [...new Set([
    ...((transaksiTunai || []).map((t: any) => t.created_by)),
    ...((hutangTunai || []).map((r: any) => r.pekerja_id)),
  ].filter(Boolean))];

  const belumDiselesai = (pid: string) => {
    const hariCash: Record<string, number> = {};
    (transaksiTunai || []).filter((t: any) => t.created_by === pid).forEach((t: any) => {
      const tk = tarikhKL(t.tarikh_masa);
      hariCash[tk] = (hariCash[tk] || 0) + (Number(t.jumlah) || 0);
    });
    (hutangTunai || []).filter((r: any) => r.pekerja_id === pid).forEach((r: any) => {
      const tk = tarikhKL(r.created_at);
      hariCash[tk] = (hariCash[tk] || 0) + (Number(r.jumlah) || 0);
    });
    const baucarIkutHari: Record<string, any> = {};
    (baucarHarian || []).filter((v: any) => v.pekerja_id === pid).forEach((v: any) => { baucarIkutHari[v.tarikh] = v; });
    return Object.entries(hariCash).reduce((a, [tarikh, cashHari]) => {
      const v = baucarIkutHari[tarikh];
      if (!v) return a + cashHari;
      return a + Math.max(0, cashHari - (Number(v.jumlah) || 0));
    }, 0);
  };
  const diserahkan = (pid: string) =>
    (serahanCash || []).filter((r: any) => r.pekerja_id === pid && r.status !== "ditolak").reduce((a: number, r: any) => a + (Number(r.jumlah) || 0), 0);

  return pekerjaIds
    .map((pid) => ({ id: pid, nama: namaOf(pid), pegang: belumDiselesai(pid) - diserahkan(pid) }))
    .filter((p) => Math.abs(p.pegang) > 0.005)
    .sort((a, b) => b.pegang - a.pegang);
}

async function cmdCash(chatId: number) {
  const senarai = await kiraCashSemuaPekerja();
  if (!senarai.length) { await sendMessage(chatId, "✅ Tiada pekerja memegang cash belum diserahkan buat masa ini.", withMenu()); return; }
  const jumlah = senarai.reduce((a, p) => a + p.pegang, 0);
  let t = `💰 Cash Dipegang (semua pekerja)\nJumlah keseluruhan: ${fmtRM(jumlah)}\n`;
  for (const p of senarai) t += `\n• ${p.nama}: ${fmtRM(p.pegang)}`;
  await sendMessage(chatId, t, withMenu());
}

async function cmdHutang(chatId: number) {
  const { data: kedaiList } = await sb.from("kedai").select("id,nama,hutang").gt("hutang", 0).order("hutang", { ascending: false }).limit(25);
  if (!kedaiList?.length) { await sendMessage(chatId, "✅ Tiada kedai berhutang buat masa ini.", withMenu()); return; }
  const ids = kedaiList.map((k: any) => k.id);
  const { data: hutangTx } = await sb.from("transaksi").select("kedai_id,tarikh_akhir_bayaran").eq("status", "hutang").in("kedai_id", ids);
  const today = tarikhKL();
  const terawalMap: Record<string, string> = {};
  (hutangTx || []).forEach((t: any) => {
    if (!t.tarikh_akhir_bayaran) return;
    if (!terawalMap[t.kedai_id] || t.tarikh_akhir_bayaran < terawalMap[t.kedai_id]) terawalMap[t.kedai_id] = t.tarikh_akhir_bayaran;
  });
  const jumlah = kedaiList.reduce((a: number, k: any) => a + (Number(k.hutang) || 0), 0);
  let t = `📋 Hutang Kedai Tertunggak (${kedaiList.length})\nJumlah keseluruhan: ${fmtRM(jumlah)}\n`;
  for (const k of kedaiList) {
    const tarikh = terawalMap[k.id];
    const lewat = tarikh && tarikh < today;
    t += `\n• ${k.nama}: ${fmtRM(k.hutang)}${tarikh ? ` — akhir bayar ${fmtD(tarikh)}${lewat ? " ⚠️ LEWAT" : ""}` : ""}`;
  }
  await sendMessage(chatId, t, withMenu());
}

async function cmdStok(chatId: number) {
  const { data: tetapan } = await sb.from("tetapan").select("stok_ambang_minimum").eq("id", 1).maybeSingle();
  const ambang = tetapan?.stok_ambang_minimum ?? 10;
  const { data: stokList } = await sb.from("stok").select("nama,stok,unit").eq("aktif", true).lte("stok", ambang).order("stok", { ascending: true }).limit(25);
  if (!stokList?.length) { await sendMessage(chatId, `✅ Tiada produk stok rendah (ambang ${ambang} unit) buat masa ini.`, withMenu()); return; }
  let t = `📦 Stok Rendah / Perlu Restock (ambang ≤${ambang})\n`;
  for (const s of stokList) t += `\n• ${s.nama}: ${s.stok} ${s.unit || "unit"}${s.stok <= 0 ? " ⚠️ HABIS" : ""}`;
  await sendMessage(chatId, t, withMenu());
}

async function cmdJualan(chatId: number) {
  const today = tarikhKL();
  const { data: tx } = await sb.from("transaksi").select("jumlah,kaedah_bayaran,status,tarikh_masa").order("tarikh_masa", { ascending: false }).limit(500);
  const hariIni = (tx || []).filter((t: any) => tarikhKL(t.tarikh_masa) === today && t.status !== "batal");
  if (!hariIni.length) { await sendMessage(chatId, "ℹ️ Tiada jualan direkodkan hari ini setakat ini.", withMenu()); return; }
  const jumlah = hariIni.reduce((a: number, t: any) => a + (Number(t.jumlah) || 0), 0);
  const ikutKaedah: Record<string, number> = {};
  hariIni.forEach((t: any) => { ikutKaedah[t.kaedah_bayaran || "?"] = (ikutKaedah[t.kaedah_bayaran || "?"] || 0) + (Number(t.jumlah) || 0); });
  let t = `🛒 Ringkasan Jualan Hari Ini (${fmtD(today)})\n${hariIni.length} transaksi — Jumlah: ${fmtRM(jumlah)}\n`;
  for (const [kaedah, j] of Object.entries(ikutKaedah)) t += `\n• ${kaedah}: ${fmtRM(j)}`;
  await sendMessage(chatId, t, withMenu());
}

async function cmdPekerja(chatId: number) {
  const cashList = await kiraCashSemuaPekerja();
  const [{ data: cash }, { data: cuti }, { data: hutang }, { data: produk }] = await Promise.all([
    sb.from("serahan_cash").select("pekerja_id").eq("status", "menunggu"),
    sb.from("permohonan_cuti").select("pekerja_id").eq("status", "menunggu"),
    sb.from("permohonan_bayaran_hutang").select("pekerja_id").eq("status", "menunggu"),
    sb.from("serahan_produk").select("pekerja_id").eq("status", "menunggu"),
  ]);
  const pendingCount: Record<string, number> = {};
  [...(cash || []), ...(cuti || []), ...(hutang || []), ...(produk || [])].forEach((r: any) => {
    pendingCount[r.pekerja_id] = (pendingCount[r.pekerja_id] || 0) + 1;
  });
  const { data: profiles } = await sb.from("profiles").select("id,nama").eq("role", "pekerja").eq("status", "aktif");
  let t = `👥 Ringkasan Pekerja Aktif (${profiles?.length || 0})\n`;
  for (const p of profiles || []) {
    const pegang = cashList.find((c) => c.id === p.id)?.pegang || 0;
    const pending = pendingCount[p.id] || 0;
    t += `\n• ${p.nama}: cash ${fmtRM(pegang)}${pending ? ` · ${pending} permohonan menunggu` : ""}`;
  }
  await sendMessage(chatId, t, withMenu());
}

async function cmdTransfer(chatId: number) {
  const tujuhHariLalu = new Date(Date.now() - 7 * 86400000).toISOString();
  const { data: tx } = await sb.from("transaksi").select("kedai_id,nama_pembeli,jumlah,resit,tarikh_masa,created_by")
    .eq("kaedah_bayaran", "transfer").gte("tarikh_masa", tujuhHariLalu).order("tarikh_masa", { ascending: false }).limit(25);
  if (!tx?.length) { await sendMessage(chatId, "✅ Tiada tempahan Online Transfer dlm 7 hari lepas.", withMenu()); return; }
  const kedaiIds = [...new Set(tx.map((t: any) => t.kedai_id).filter(Boolean))];
  const { data: kedaiList } = kedaiIds.length ? await sb.from("kedai").select("id,nama").in("id", kedaiIds) : { data: [] as any[] };
  const namaKedai = (id: string) => kedaiList?.find((k: any) => k.id === id)?.nama || id;
  let t = `💳 Tempahan Online Transfer (7 hari lepas) — sila sahkan duit SUDAH masuk bank:\n`;
  for (const r of tx) t += `\n• ${r.kedai_id ? namaKedai(r.kedai_id) : (r.nama_pembeli || "Pelanggan")} — ${fmtRM(r.jumlah)} — #${r.resit || "-"} (${tarikhKL(r.tarikh_masa)})`;
  await sendMessage(chatId, t, withMenu());
}

async function cmdBaucar(chatId: number) {
  const { data } = await sb.from("baucar_bayaran").select("*").eq("kategori", "upah_harian").eq("status", "draf").order("tarikh", { ascending: false }).limit(20);
  if (!data?.length) { await sendMessage(chatId, "✅ Tiada baucar harian (draf) menunggu semakan.", withMenu()); return; }
  const { data: profiles } = await sb.from("profiles").select("id,nama");
  const namaOf = (id: string) => profiles?.find((p: any) => p.id === id)?.nama || id;
  await sendMessage(chatId, `🕐 ${data.length} Baucar Harian (Draf) Menunggu Semakan:`, withMenu());
  for (const r of data) {
    await sendMessage(chatId,
      `🧾 Baucar Harian\n👤 ${namaOf(r.pekerja_id)}\n${fmtD(r.tarikh)} — Upah ${fmtRM(r.jumlah)}\nCash tangan ${fmtRM(r.cash_ditangan)} | Baki serah ${fmtRM(r.baki)}`,
      withMenu(kbBaucar(r.id)));
  }
}

async function cmdPadam(chatId: number) {
  const { data } = await sb.from("permohonan_padam").select("*").eq("status", "menunggu").order("created_at", { ascending: false }).limit(20);
  if (!data?.length) { await sendMessage(chatId, "✅ Tiada permohonan padam menunggu.", withMenu()); return; }
  const { data: profiles } = await sb.from("profiles").select("id,nama");
  const namaOf = (id: string) => profiles?.find((p: any) => p.id === id)?.nama || id;
  let t = `🗑️ ${data.length} Permohonan Padam Menunggu (baca sahaja)\nPadam rekod perlu disemak teliti (KEKAL/tak boleh diundur) — sila buka Sistem Pengurusan utk putuskan:\n`;
  for (const r of data) t += `\n• ${r.rekod_label || r.rekod_id} (${r.jenis}) — ${namaOf(r.pekerja_id)}${r.sebab ? " — " + r.sebab : ""}`;
  await sendMessage(chatId, t, withMenu());
}

async function cmdMenunggu(chatId: number) {
  const [{ data: cash }, { data: cuti }, { data: hutang }, { data: produk }, { data: padam }, { data: baucar }, { data: profiles }] = await Promise.all([
    sb.from("serahan_cash").select("*").eq("status", "menunggu").order("created_at"),
    sb.from("permohonan_cuti").select("*").eq("status", "menunggu").order("created_at"),
    sb.from("permohonan_bayaran_hutang").select("*").eq("status", "menunggu").order("created_at"),
    sb.from("serahan_produk").select("*").eq("status", "menunggu").order("created_at"),
    sb.from("permohonan_padam").select("*").eq("status", "menunggu").order("created_at"),
    sb.from("baucar_bayaran").select("*").eq("kategori", "upah_harian").eq("status", "draf").order("tarikh", { ascending: false }),
    sb.from("profiles").select("id,nama"),
  ]);
  const namaOf = (id: string) => profiles?.find((p: any) => p.id === id)?.nama || id;
  const total = (cash?.length || 0) + (cuti?.length || 0) + (hutang?.length || 0) + (produk?.length || 0) + (padam?.length || 0) + (baucar?.length || 0);
  if (!total) { await sendMessage(chatId, "✅ Tiada permohonan menunggu kelulusan buat masa ini.", withMenu()); return; }
  await sendMessage(chatId, `🔔 ${total} permohonan menunggu kelulusan:`, withMenu());

  for (const r of (cash || []).slice(0, 8)) {
    await sendMessage(chatId, `💵 Serahan Cash\n👤 ${namaOf(r.pekerja_id)}\n${fmtRM(r.jumlah)}${r.nota ? "\nNota: " + r.nota : ""}`, withMenu(kb("sc", r.id)));
  }
  for (const r of (cuti || []).slice(0, 8)) {
    await sendMessage(chatId, `🌴 ${r.jenis}\n👤 ${namaOf(r.pekerja_id)}\n${fmtD(r.tarikh_mula)} - ${fmtD(r.tarikh_tamat)}${r.nota ? "\nNota: " + r.nota : ""}`, withMenu(kb("cu", r.id)));
  }
  for (const r of (hutang || []).slice(0, 8)) {
    const sasaran = r.kedai_id || `${r.nama_pembeli || "?"} (Peribadi)`;
    await sendMessage(chatId, `💳 Bayaran Hutang\n👤 ${namaOf(r.pekerja_id)}\n🎯 ${sasaran}\n${fmtRM(r.jumlah)} (${r.kaedah_bayaran})${r.settlement_penuh ? " · PENUH" : ""}`, withMenu(kb("bh", r.id)));
  }
  for (const r of (produk || []).slice(0, 8)) {
    const label = r.jenis === "ambil" ? "Permohonan Ambil Stok" : r.jenis === "baik" ? "Serahan Produk (Baik)" : "Serahan Produk (Reject)";
    await sendMessage(chatId, `📦 ${label}\n👤 ${namaOf(r.pekerja_id)}\n${r.stok_nama} ×${r.kuantiti}${r.sebab ? "\nSebab: " + r.sebab : ""}`, withMenu(kb("sp", r.id)));
  }
  for (const r of (baucar || []).slice(0, 8)) {
    await sendMessage(chatId, `🧾 Baucar Harian\n👤 ${namaOf(r.pekerja_id)}\n${fmtD(r.tarikh)} — Upah ${fmtRM(r.jumlah)}\nCash tangan ${fmtRM(r.cash_ditangan)} | Baki serah ${fmtRM(r.baki)}`, withMenu(kbBaucar(r.id)));
  }
  if (padam?.length) {
    let t = `🗑️ ${padam.length} permohonan padam (baca sahaja — buka Sistem Pengurusan):`;
    for (const r of padam.slice(0, 8)) t += `\n• ${r.rekod_label || r.rekod_id} (${r.jenis}) — ${namaOf(r.pekerja_id)}`;
    await sendMessage(chatId, t, withMenu());
  }
}

async function cmdStatus(chatId: number) {
  const [cashList, { count: hutangCount }, { data: tetapan }, { count: menungguCash }, { count: menungguCuti }, { count: menungguHutang }, { count: menungguProduk }, { count: baucarDraf }] = await Promise.all([
    kiraCashSemuaPekerja(),
    sb.from("kedai").select("id", { count: "exact", head: true }).gt("hutang", 0),
    sb.from("tetapan").select("stok_ambang_minimum").eq("id", 1).maybeSingle(),
    sb.from("serahan_cash").select("id", { count: "exact", head: true }).eq("status", "menunggu"),
    sb.from("permohonan_cuti").select("id", { count: "exact", head: true }).eq("status", "menunggu"),
    sb.from("permohonan_bayaran_hutang").select("id", { count: "exact", head: true }).eq("status", "menunggu"),
    sb.from("serahan_produk").select("id", { count: "exact", head: true }).eq("status", "menunggu"),
    sb.from("baucar_bayaran").select("id", { count: "exact", head: true }).eq("kategori", "upah_harian").eq("status", "draf"),
  ]);
  const ambang = tetapan?.stok_ambang_minimum ?? 10;
  const { count: stokRendahCount } = await sb.from("stok").select("id", { count: "exact", head: true }).eq("aktif", true).lte("stok", ambang);
  const jumlahCash = cashList.reduce((a, p) => a + p.pegang, 0);
  const totalMenunggu = (menungguCash || 0) + (menungguCuti || 0) + (menungguHutang || 0) + (menungguProduk || 0) + (baucarDraf || 0);
  const t = `📊 Status Ringkas Wafi Tijarah Trading\n` +
    `\n💰 Cash dipegang pekerja: ${fmtRM(jumlahCash)} (${cashList.length} pekerja)` +
    `\n📋 Kedai berhutang: ${hutangCount || 0}` +
    `\n🔔 Permohonan menunggu kelulusan: ${totalMenunggu} (termasuk ${baucarDraf || 0} baucar harian draf)` +
    `\n📦 Produk stok rendah: ${stokRendahCount || 0}` +
    `\n\nTaip /menunggu utk lulus/tolak, /help utk senarai penuh arahan.`;
  await sendMessage(chatId, t, withMenu());
}

function cmdHelp(chatId: number) {
  return sendMessage(chatId,
    "🤖 Arahan Bot Wafi Tijarah Trading\n" +
    "\n/menu — Papar menu utama (butang, tak perlu ingat arahan)\n" +
    "/status — Ringkasan cepat semua\n" +
    "/cash — Cash dipegang semua pekerja\n" +
    "/hutang — Hutang kedai tertunggak/lewat\n" +
    "/menunggu — Permohonan menunggu (boleh Lulus/Tolak)\n" +
    "/baucar — Baucar harian (draf) menunggu semakan — boleh Lulus/Batal\n" +
    "/stok — Stok rendah/perlu restock\n" +
    "/jualan — Ringkasan jualan hari ini\n" +
    "/pekerja — Status cash & permohonan setiap pekerja\n" +
    "/transfer — Tempahan online transfer (7 hari) — sahkan bank\n" +
    "/padam — Senarai permohonan padam (baca sahaja)\n" +
    "/laporan — Laporan harian PENUH hari ini setakat sekarang\n" +
    "/laporan harian — Laporan harian PENUH hari semalam (hari lengkap) — dihantar AUTOMATIK jugak setiap pukul 8 pagi\n" +
    "/mute — Matikan notifikasi automatik ke chat ini\n" +
    "/unmute — Hidupkan semula notifikasi automatik\n" +
    "\nSemua butang ✅ Lulus / ✕ Tolak bertindak SERTA-MERTA — sila semak butiran dahulu. Taip /menu bila-bila utk kembali ke menu.", withMenu());
}

// ── SQL_TAMBAHAN_148: /laporan & /laporan harian + auto 8 pagi ──
async function ringkasanKehadiranTarikh(tarikh: string) {
  const dariUTC = new Date(`${tarikh}T00:00:00+08:00`).toISOString();
  const hinggaUTC = new Date(`${tarikh}T23:59:59+08:00`).toISOString();
  const { data } = await sb.from("kehadiran").select("pekerja_id,thumb_in_masa,thumb_out_masa")
    .gte("thumb_in_masa", dariUTC).lte("thumb_in_masa", hinggaUTC).order("thumb_in_masa");
  return data || [];
}
async function ringkasanJualanTarikh(tarikh: string) {
  const { data: tx } = await sb.from("transaksi").select("jumlah,kaedah_bayaran,status,tarikh_masa").order("tarikh_masa", { ascending: false }).limit(1000);
  return (tx || []).filter((t: any) => tarikhKL(t.tarikh_masa) === tarikh && t.status !== "batal");
}
async function bangunLaporan(tarikh: string): Promise<string> {
  const [kehadiran, jualanHari, { data: baucarHari }, cashList, { count: hutangCount }, { data: tetapan }, { count: menungguCash }, { count: menungguCuti }, { count: menungguHutang }, { count: menungguProduk }, { count: baucarDraf }, { data: profiles }] = await Promise.all([
    ringkasanKehadiranTarikh(tarikh),
    ringkasanJualanTarikh(tarikh),
    sb.from("baucar_bayaran").select("status,jumlah").eq("kategori", "upah_harian").eq("tarikh", tarikh),
    kiraCashSemuaPekerja(),
    sb.from("kedai").select("id", { count: "exact", head: true }).gt("hutang", 0),
    sb.from("tetapan").select("stok_ambang_minimum").eq("id", 1).maybeSingle(),
    sb.from("serahan_cash").select("id", { count: "exact", head: true }).eq("status", "menunggu"),
    sb.from("permohonan_cuti").select("id", { count: "exact", head: true }).eq("status", "menunggu"),
    sb.from("permohonan_bayaran_hutang").select("id", { count: "exact", head: true }).eq("status", "menunggu"),
    sb.from("serahan_produk").select("id", { count: "exact", head: true }).eq("status", "menunggu"),
    sb.from("baucar_bayaran").select("id", { count: "exact", head: true }).eq("kategori", "upah_harian").eq("status", "draf"),
    sb.from("profiles").select("id,nama"),
  ]);
  const namaOf = (id: string) => profiles?.find((p: any) => p.id === id)?.nama || id;
  const ambang = tetapan?.stok_ambang_minimum ?? 10;
  const { count: stokRendahCount } = await sb.from("stok").select("id", { count: "exact", head: true }).eq("aktif", true).lte("stok", ambang);

  let t = `📰 Laporan Harian — ${fmtD(tarikh)}`;

  t += `\n\n🕐 KEHADIRAN (${kehadiran.length} sesi)`;
  if (!kehadiran.length) t += `\nTiada rekod thumb-in pada tarikh ini.`;
  for (const k of kehadiran as any[]) {
    t += `\n• ${namaOf(k.pekerja_id)}: ${fmtJam(k.thumb_in_masa)}–${k.thumb_out_masa ? fmtJam(k.thumb_out_masa) : "?"} (${fmtDurasi(k.thumb_in_masa, k.thumb_out_masa)})`;
  }

  const jumlahJualan = jualanHari.reduce((a: number, x: any) => a + (Number(x.jumlah) || 0), 0);
  t += `\n\n🛒 JUALAN: ${jualanHari.length} transaksi — ${fmtRM(jumlahJualan)}`;
  const ikutKaedah: Record<string, number> = {};
  jualanHari.forEach((x: any) => { ikutKaedah[x.kaedah_bayaran || "?"] = (ikutKaedah[x.kaedah_bayaran || "?"] || 0) + (Number(x.jumlah) || 0); });
  for (const [kaedah, j] of Object.entries(ikutKaedah)) t += `\n• ${kaedah}: ${fmtRM(j)}`;

  const bJumlah = (baucarHari || []).reduce((a: number, x: any) => a + (Number(x.jumlah) || 0), 0);
  t += `\n\n🧾 BAUCAR HARIAN: ${(baucarHari || []).length} baucar — ${fmtRM(bJumlah)}`;
  const ikutStatus: Record<string, number> = {};
  (baucarHari || []).forEach((x: any) => { ikutStatus[x.status] = (ikutStatus[x.status] || 0) + 1; });
  for (const [st, n] of Object.entries(ikutStatus)) t += `\n• ${st}: ${n}`;

  const jumlahCash = cashList.reduce((a, p) => a + p.pegang, 0);
  t += `\n\n💰 CASH DIPEGANG (terkini): ${fmtRM(jumlahCash)} (${cashList.length} pekerja)`;
  t += `\n\n📋 HUTANG KEDAI TERTUNGGAK (terkini): ${hutangCount || 0} kedai`;
  t += `\n\n📦 STOK RENDAH (terkini): ${stokRendahCount || 0} produk`;

  const totalMenunggu = (menungguCash || 0) + (menungguCuti || 0) + (menungguHutang || 0) + (menungguProduk || 0) + (baucarDraf || 0);
  t += `\n\n🔔 PERMOHONAN MENUNGGU KELULUSAN: ${totalMenunggu}`;
  t += `\n\nTaip /hutang, /stok atau /menunggu utk butiran penuh.`;
  return t;
}
async function cmdLaporan(chatId: number, args: string[]) {
  const arg = (args[0] || "").toLowerCase();
  const tarikh = (arg === "semalam" || arg === "harian") ? tarikhSemalamKL() : tarikhKL();
  const teks = await bangunLaporan(tarikh);
  await sendMessage(chatId, teks, withMenu());
}

const MENU_CMDS: Record<string, (chatId: number, args: string[]) => Promise<unknown>> = {
  status: (c) => cmdStatus(c),
  cash: (c) => cmdCash(c),
  hutang: (c) => cmdHutang(c),
  menunggu: (c) => cmdMenunggu(c),
  baucar: (c) => cmdBaucar(c),
  stok: (c) => cmdStok(c),
  jualan: (c) => cmdJualan(c),
  pekerja: (c) => cmdPekerja(c),
  transfer: (c) => cmdTransfer(c),
  padam: (c) => cmdPadam(c),
  laporan: (c, a) => cmdLaporan(c, a),
  help: (c) => Promise.resolve(cmdHelp(c)),
};

Deno.serve(async (req) => {
  const url = new URL(req.url);

  // ── Aksi pentadbiran sekali-sahaja: daftar webhook dgn Telegram ──
  // (dipanggil oleh pembangun/pemilik selepas TELEGRAM_BOT_TOKEN &
  // TELEGRAM_WEBHOOK_SECRET ditetapkan sbg Edge Function secrets — token
  // TIDAK PERNAH dipaparkan/dihantar keluar drpd fungsi ni.)
  if (url.searchParams.get("setup") === "1") {
    const key = req.headers.get("x-setup-key");
    if (!WEBHOOK_SECRET || !BOT_TOKEN || key !== WEBHOOK_SECRET) return json({ error: "unauthorized" }, 401);
    const me = await tg("getMe", {});
    const webhookUrl = `${SUPABASE_URL}/functions/v1/telegram-webhook`;
    const setRes = await tg("setWebhook", {
      url: webhookUrl,
      secret_token: WEBHOOK_SECRET,
      allowed_updates: ["message", "callback_query"],
      drop_pending_updates: true,
    });
    return json({ ok: true, bot: me.result, setWebhook: setRes, webhookUrl });
  }

  // ── SQL_TAMBAHAN_148: dipanggil oleh pg_cron (job "laporan-harian-8am")
  // setiap pukul 8 pagi waktu Malaysia — hantar /laporan harian (hari
  // SEMALAM, hari lengkap) kpd SEMUA chat pemilik aktif & notifikasi_aktif.
  // Dikunci dgn secret BERASINGAN (CRON_LAPORAN_SECRET) drpd webhook secret
  // Telegram — bukan endpoint awam.
  if (url.searchParams.get("cron") === "laporan") {
    const key = req.headers.get("x-cron-key");
    if (!CRON_KEY || key !== CRON_KEY) return json({ error: "unauthorized" }, 401);
    const tarikh = tarikhSemalamKL();
    const teks = await bangunLaporan(tarikh);
    const { data: adminList } = await sb.from("telegram_admin").select("chat_id").eq("aktif", true).eq("notifikasi_aktif", true);
    let dihantar = 0;
    for (const a of (adminList || []) as any[]) {
      try { await sendMessage(a.chat_id, teks, withMenu()); dihantar++; } catch (err) { console.warn(`[telegram-webhook] laporan cron gagal chat_id=${a.chat_id}`, err); }
    }
    return json({ ok: true, tarikh, dihantar });
  }

  if (req.method !== "POST") return json({ ok: true });

  const secretHeader = req.headers.get("x-telegram-bot-api-secret-token");
  if (!WEBHOOK_SECRET || secretHeader !== WEBHOOK_SECRET) return json({ error: "unauthorized" }, 401);

  let update: any;
  try { update = await req.json(); } catch { return json({ ok: true }); }

  try {
    if (update.callback_query) {
      const cq = update.callback_query;
      const chatId = cq.message?.chat?.id;
      const messageId = cq.message?.message_id;
      const data = String(cq.data || "");
      const admin = chatId ? await getAdmin(chatId) : null;
      if (!admin) { await answerCallback(cq.id, "Chat ini tiada kebenaran pemilik.", true); return json({ ok: true }); }

      const parts = data.split(":");

      if (parts[0] === "mnu") {
        const key = parts[1];
        if (key === "menu") { await answerCallback(cq.id); await cmdMenu(chatId); return json({ ok: true }); }
        const fn = MENU_CMDS[key];
        if (!fn) { await answerCallback(cq.id, "Arahan tidak dikenali.", true); return json({ ok: true }); }
        await answerCallback(cq.id);
        await fn(chatId, []);
        return json({ ok: true });
      }

      if (parts[0] !== "tp" || parts.length !== 4 || !CODE_JADUAL[parts[1]]) {
        await answerCallback(cq.id, "Data tidak sah.", true);
        return json({ ok: true });
      }
      const [, code, id, action] = parts;
      const jadual = CODE_JADUAL[code];
      const status = action === "A" ? "disahkan" : "ditolak";

      const { data: hasil, error } = await sb.rpc("telegram_putuskan", { p_admin_chat_id: chatId, p_jadual: jadual, p_id: id, p_status: status });
      if (error) {
        await answerCallback(cq.id, "❌ " + error.message, true);
        return json({ ok: true });
      }
      await answerCallback(cq.id, hasil || "Selesai");
      const asalText = cq.message?.text || "";
      await editText(chatId, messageId, `${asalText}\n\n➡️ ${hasil}\n👤 oleh ${admin.nama} · ${nowKLDisplay()}`);
      return json({ ok: true });
    }

    if (update.message) {
      const msg = update.message;
      const chatId = msg.chat?.id;
      const text = String(msg.text || "").trim();
      if (!chatId || !text) return json({ ok: true });

      const [cmdRaw, ...args] = text.split(/\s+/);
      const cmd = cmdRaw.toLowerCase().replace(/@\w+$/, "");

      if (cmd === "/link") {
        const kod = (args[0] || "").toUpperCase().trim();
        if (!kod) { await sendMessage(chatId, "Sila hantar: /link KOD (jana kod di Sistem Pengurusan > Lebih > Tetapan Telegram)"); return json({ ok: true }); }
        const { data: kodRow } = await sb.from("telegram_link_codes").select("*").eq("code", kod).eq("used", false).maybeSingle();
        if (!kodRow || new Date(kodRow.expires_at).getTime() < Date.now()) {
          await sendMessage(chatId, "❌ Kod tidak sah atau sudah tamat tempoh. Jana kod baharu di Sistem Pengurusan.");
          return json({ ok: true });
        }
        const { data: profil } = await sb.from("profiles").select("id,nama,role").eq("id", kodRow.user_id).maybeSingle();
        if (!profil || profil.role !== "pemilik") {
          await sendMessage(chatId, "❌ Akaun berkaitan bukan akaun pemilik.");
          return json({ ok: true });
        }
        await sb.from("telegram_admin").upsert({ chat_id: chatId, user_id: profil.id, nama: profil.nama, aktif: true, notifikasi_aktif: true }, { onConflict: "chat_id" });
        await sb.from("telegram_link_codes").update({ used: true }).eq("code", kod);
        await sendMessage(chatId, `✅ Berjaya dipautkan sebagai ${profil.nama}!\n\nTaip /help utk senarai arahan.`);
        return json({ ok: true });
      }

      if (cmd === "/start") {
        const admin = await getAdmin(chatId);
        if (admin) await sendMessage(chatId, `👋 Selamat kembali, ${admin.nama}!\nTaip /help utk senarai arahan.`);
        else await sendMessage(chatId, "👋 Selamat datang ke Bot Wafi Tijarah Trading.\n\nUntuk pautkan chat ini sebagai pemilik, jana kod di Sistem Pengurusan (Lebih > Tetapan Telegram) lalu hantar:\n/link KOD");
        return json({ ok: true });
      }

      const admin = await getAdmin(chatId);
      if (!admin) {
        await sendMessage(chatId, "Chat ini belum dipautkan. Jana kod di Sistem Pengurusan (Lebih > Tetapan Telegram) lalu hantar:\n/link KOD");
        return json({ ok: true });
      }

      switch (cmd) {
        case "/menu": await cmdMenu(chatId); break;
        case "/help": await cmdHelp(chatId); break;
        case "/status": await cmdStatus(chatId); break;
        case "/cash": await cmdCash(chatId); break;
        case "/hutang": await cmdHutang(chatId); break;
        case "/menunggu": await cmdMenunggu(chatId); break;
        case "/baucar": await cmdBaucar(chatId); break;
        case "/stok": await cmdStok(chatId); break;
        case "/jualan": await cmdJualan(chatId); break;
        case "/pekerja": await cmdPekerja(chatId); break;
        case "/transfer": await cmdTransfer(chatId); break;
        case "/padam": await cmdPadam(chatId); break;
        case "/laporan": await cmdLaporan(chatId, args); break;
        case "/mute":
          await sb.from("telegram_admin").update({ notifikasi_aktif: false }).eq("chat_id", chatId);
          await sendMessage(chatId, "🔕 Notifikasi automatik dimatikan utk chat ini. Taip /unmute utk hidupkan semula.");
          break;
        case "/unmute":
          await sb.from("telegram_admin").update({ notifikasi_aktif: true }).eq("chat_id", chatId);
          await sendMessage(chatId, "🔔 Notifikasi automatik dihidupkan semula.");
          break;
        default:
          await sendMessage(chatId, "Arahan tak dikenali. Taip /help utk senarai arahan.");
      }
      return json({ ok: true });
    }

    return json({ ok: true });
  } catch (e) {
    console.error("[telegram-webhook] ralat:", e);
    return json({ ok: true }); // sentiasa 200 kpd Telegram supaya ia tak retry berulang-ulang
  }
});
