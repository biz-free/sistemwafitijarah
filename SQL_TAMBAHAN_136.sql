-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 136: Indikator Sah Lokasi Kedai (🔴🟡🟢) — elak km/minyak salah kira
--
-- PUNCA: Pin lokasi kedai diletak MANUAL (seret/klik peta atau cari alamat) semasa
-- daftar/edit — tiada semakan sama sekali sebelum ni. Pin tersasar (walau beberapa
-- km) terus jejaskan kiraan jarak (kiraJarakKehadiranJulat/jarakSesiKehadiran) dan
-- kos minyak/upah dalam Laporan & Baucar Harian. Lihat siasatan sebenar Agrobazaar
-- Seri Indah Bakery (Sep 2026) — kedai tu ~22km terasing drpd kedai lain hari sama.
--
-- PENYELESAIAN: simpan jarak (km) antara pin kedai DENGAN GPS semasa PEKERJA pada
-- masa didaftar/dikemaskini (null = tak dapat disahkan — pemilik daftar drpd
-- pejabat, atau GPS ditolak/gagal — bukan ralat). Dipapar sbg badge 🔴🟡🟢 LIVE
-- dlm borang Daftar/Edit Kedai (pengurusan.html), + diguna semula sbg amaran kpd
-- PEMILIK dlm senarai Baucar Bayaran SEBELUM baucar harian diluluskan (gabung dgn
-- semakan "kedai terasing drpd kedai lain hari sama" — isyarat kedua ni berfungsi
-- utk SEMUA kedai, termasuk yg didaftar sebelum ciri ni wujud).
-- ═══════════════════════════════════════════════════════════

ALTER TABLE kedai ADD COLUMN IF NOT EXISTS jarak_pin_gps_km numeric;
