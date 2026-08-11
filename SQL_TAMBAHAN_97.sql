-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 97: Betulkan semula harga MODAL semua produk (gantikan
-- SQL_TAMBAHAN_96 — pemilik jelaskan struktur harga sebenar selepas
-- perbincangan). Harga jualan SEDIA ADA (cth Tamar Cocoa 900g RM26)
-- sebenarnya = Harga Jual ASAL (RM25, sasaran untung 20% drpd jualan)
-- + RM1 tambahan flat utk cover kos operasi (BUKAN sebahagian daripada
-- untung 20%). Jadi:
--
--   Modal = (Harga Jual SEKARANG − RM1) × 80%
--
-- KECUALI "Tamar Cocoa Papan (Gerai/Kedai Makan)" (S2681163) — sachet
-- kecil dipecah drpd pek 20, RM1 flat TAK RELEVAN pada harga RM1.20,
-- kekal formula asal tanpa tolak RM1:
--
--   Modal = Harga Jual × 80%
--
-- Disahkan kpd pemilik via pratonton jadual penuh sblm laksana.
-- ═══════════════════════════════════════════════════════════

UPDATE public.stok
SET harga_beli = CASE
  WHEN id = 'S2681163' THEN round((harga_jual * 0.8)::numeric, 2)
  ELSE round(((harga_jual - 1) * 0.8)::numeric, 2)
END;
