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

import { createClient } from "npm:@supabase/supabase-js@2";

const BOT_TOKEN = Deno.env.get("TELEGRAM_BOT_TOKEN") || "";
const WEBHOOK_SECRET = Deno.env.get("TELEGRAM_WEBHOOK_SECRET") || "";
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
  if (!senarai.length) { await sendMessage(chatId, "✅ Tiada pekerja memegang cash belum diserahkan buat masa ini."); return; }
  const jumlah = senarai.reduce((a, p) => a + p.pegang, 0);
  let t = `💰 Cash Dipegang (semua pekerja)\nJumlah keseluruhan: ${fmtRM(jumlah)}\n`;
  for (const p of senarai) t += `\n• ${p.nama}: ${fmtRM(p.pegang)}`;
  await sendMessage(chatId, t);
}

async function cmdHutang(chatId: number) {
  const { data: kedaiList } = await sb.from("kedai").select("id,nama,hutang").gt("hutang", 0).order("hutang", { ascending: false }).limit(25);
  if (!kedaiList?.length) { await sendMessage(chatId, "✅ Tiada kedai berhutang buat masa ini."); return; }
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
  await sendMessage(chatId, t);
}

async function cmdStok(chatId: number) {
  const { data: tetapan } = await sb.from("tetapan").select("stok_ambang_minimum").eq("id", 1).maybeSingle();
  const ambang = tetapan?.stok_ambang_minimum ?? 10;
  const { data: stokList } = await sb.from("stok").select("nama,stok,unit").eq("aktif", true).lte("stok", ambang).order("stok", { ascending: true }).limit(25);
  if (!stokList?.length) { await sendMessage(chatId, `✅ Tiada produk stok rendah (ambang ${ambang} unit) buat masa ini.`); return; }
  let t = `📦 Stok Rendah / Perlu Restock (ambang ≤${ambang})\n`;
  for (const s of stokList) t += `\n• ${s.nama}: ${s.stok} ${s.unit || "unit"}${s.stok <= 0 ? " ⚠️ HABIS" : ""}`;
  await sendMessage(chatId, t);
}

async function cmdJualan(chatId: number) {
  const today = tarikhKL();
  const { data: tx } = await sb.from("transaksi").select("jumlah,kaedah_bayaran,status,tarikh_masa").order("tarikh_masa", { ascending: false }).limit(500);
  const hariIni = (tx || []).filter((t: any) => tarikhKL(t.tarikh_masa) === today && t.status !== "batal");
  if (!hariIni.length) { await sendMessage(chatId, "ℹ️ Tiada jualan direkodkan hari ini setakat ini."); return; }
  const jumlah = hariIni.reduce((a: number, t: any) => a + (Number(t.jumlah) || 0), 0);
  const ikutKaedah: Record<string, number> = {};
  hariIni.forEach((t: any) => { ikutKaedah[t.kaedah_bayaran || "?"] = (ikutKaedah[t.kaedah_bayaran || "?"] || 0) + (Number(t.jumlah) || 0); });
  let t = `🛒 Ringkasan Jualan Hari Ini (${fmtD(today)})\n${hariIni.length} transaksi — Jumlah: ${fmtRM(jumlah)}\n`;
  for (const [kaedah, j] of Object.entries(ikutKaedah)) t += `\n• ${kaedah}: ${fmtRM(j)}`;
  await sendMessage(chatId, t);
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
  await sendMessage(chatId, t);
}

async function cmdTransfer(chatId: number) {
  const tujuhHariLalu = new Date(Date.now() - 7 * 86400000).toISOString();
  const { data: tx } = await sb.from("transaksi").select("kedai_id,nama_pembeli,jumlah,resit,tarikh_masa,created_by")
    .eq("kaedah_bayaran", "transfer").gte("tarikh_masa", tujuhHariLalu).order("tarikh_masa", { ascending: false }).limit(25);
  if (!tx?.length) { await sendMessage(chatId, "✅ Tiada tempahan Online Transfer dlm 7 hari lepas."); return; }
  const kedaiIds = [...new Set(tx.map((t: any) => t.kedai_id).filter(Boolean))];
  const { data: kedaiList } = kedaiIds.length ? await sb.from("kedai").select("id,nama").in("id", kedaiIds) : { data: [] as any[] };
  const namaKedai = (id: string) => kedaiList?.find((k: any) => k.id === id)?.nama || id;
  let t = `💳 Tempahan Online Transfer (7 hari lepas) — sila sahkan duit SUDAH masuk bank:\n`;
  for (const r of tx) t += `\n• ${r.kedai_id ? namaKedai(r.kedai_id) : (r.nama_pembeli || "Pelanggan")} — ${fmtRM(r.jumlah)} — #${r.resit || "-"} (${tarikhKL(r.tarikh_masa)})`;
  await sendMessage(chatId, t);
}

async function cmdBaucar(chatId: number) {
  const { data } = await sb.from("baucar_bayaran").select("*").eq("kategori", "upah_harian").eq("status", "draf").order("tarikh", { ascending: false }).limit(20);
  if (!data?.length) { await sendMessage(chatId, "✅ Tiada baucar harian (draf) menunggu semakan."); return; }
  const { data: profiles } = await sb.from("profiles").select("id,nama");
  const namaOf = (id: string) => profiles?.find((p: any) => p.id === id)?.nama || id;
  await sendMessage(chatId, `🕐 ${data.length} Baucar Harian (Draf) Menunggu Semakan:`);
  for (const r of data) {
    await sendMessage(chatId,
      `🧾 Baucar Harian\n👤 ${namaOf(r.pekerja_id)}\n${fmtD(r.tarikh)} — Upah ${fmtRM(r.jumlah)}\nCash tangan ${fmtRM(r.cash_ditangan)} | Baki serah ${fmtRM(r.baki)}`,
      kbBaucar(r.id));
  }
}

async function cmdPadam(chatId: number) {
  const { data } = await sb.from("permohonan_padam").select("*").eq("status", "menunggu").order("created_at", { ascending: false }).limit(20);
  if (!data?.length) { await sendMessage(chatId, "✅ Tiada permohonan padam menunggu."); return; }
  const { data: profiles } = await sb.from("profiles").select("id,nama");
  const namaOf = (id: string) => profiles?.find((p: any) => p.id === id)?.nama || id;
  let t = `🗑️ ${data.length} Permohonan Padam Menunggu (baca sahaja)\nPadam rekod perlu disemak teliti (KEKAL/tak boleh diundur) — sila buka Sistem Pengurusan utk putuskan:\n`;
  for (const r of data) t += `\n• ${r.rekod_label || r.rekod_id} (${r.jenis}) — ${namaOf(r.pekerja_id)}${r.sebab ? " — " + r.sebab : ""}`;
  await sendMessage(chatId, t);
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
  if (!total) { await sendMessage(chatId, "✅ Tiada permohonan menunggu kelulusan buat masa ini."); return; }
  await sendMessage(chatId, `🔔 ${total} permohonan menunggu kelulusan:`);

  for (const r of (cash || []).slice(0, 8)) {
    await sendMessage(chatId, `💵 Serahan Cash\n👤 ${namaOf(r.pekerja_id)}\n${fmtRM(r.jumlah)}${r.nota ? "\nNota: " + r.nota : ""}`, kb("sc", r.id));
  }
  for (const r of (cuti || []).slice(0, 8)) {
    await sendMessage(chatId, `🌴 ${r.jenis}\n👤 ${namaOf(r.pekerja_id)}\n${fmtD(r.tarikh_mula)} - ${fmtD(r.tarikh_tamat)}${r.nota ? "\nNota: " + r.nota : ""}`, kb("cu", r.id));
  }
  for (const r of (hutang || []).slice(0, 8)) {
    const sasaran = r.kedai_id || `${r.nama_pembeli || "?"} (Peribadi)`;
    await sendMessage(chatId, `💳 Bayaran Hutang\n👤 ${namaOf(r.pekerja_id)}\n🎯 ${sasaran}\n${fmtRM(r.jumlah)} (${r.kaedah_bayaran})${r.settlement_penuh ? " · PENUH" : ""}`, kb("bh", r.id));
  }
  for (const r of (produk || []).slice(0, 8)) {
    const label = r.jenis === "ambil" ? "Permohonan Ambil Stok" : r.jenis === "baik" ? "Serahan Produk (Baik)" : "Serahan Produk (Reject)";
    await sendMessage(chatId, `📦 ${label}\n👤 ${namaOf(r.pekerja_id)}\n${r.stok_nama} ×${r.kuantiti}${r.sebab ? "\nSebab: " + r.sebab : ""}`, kb("sp", r.id));
  }
  for (const r of (baucar || []).slice(0, 8)) {
    await sendMessage(chatId, `🧾 Baucar Harian\n👤 ${namaOf(r.pekerja_id)}\n${fmtD(r.tarikh)} — Upah ${fmtRM(r.jumlah)}\nCash tangan ${fmtRM(r.cash_ditangan)} | Baki serah ${fmtRM(r.baki)}`, kbBaucar(r.id));
  }
  if (padam?.length) {
    let t = `🗑️ ${padam.length} permohonan padam (baca sahaja — buka Sistem Pengurusan):`;
    for (const r of padam.slice(0, 8)) t += `\n• ${r.rekod_label || r.rekod_id} (${r.jenis}) — ${namaOf(r.pekerja_id)}`;
    await sendMessage(chatId, t);
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
  await sendMessage(chatId, t);
}

function cmdHelp(chatId: number) {
  return sendMessage(chatId,
    "🤖 Arahan Bot Wafi Tijarah Trading\n" +
    "\n/status — Ringkasan cepat semua\n" +
    "/cash — Cash dipegang semua pekerja\n" +
    "/hutang — Hutang kedai tertunggak/lewat\n" +
    "/menunggu — Permohonan menunggu (boleh Lulus/Tolak)\n" +
    "/baucar — Baucar harian (draf) menunggu semakan — boleh Lulus/Batal\n" +
    "/stok — Stok rendah/perlu restock\n" +
    "/jualan — Ringkasan jualan hari ini\n" +
    "/pekerja — Status cash & permohonan setiap pekerja\n" +
    "/transfer — Tempahan online transfer (7 hari) — sahkan bank\n" +
    "/padam — Senarai permohonan padam (baca sahaja)\n" +
    "/mute — Matikan notifikasi automatik ke chat ini\n" +
    "/unmute — Hidupkan semula notifikasi automatik\n" +
    "\nSemua butang ✅ Lulus / ✕ Tolak bertindak SERTA-MERTA — sila semak butiran dahulu.");
}

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
