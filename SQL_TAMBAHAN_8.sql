-- ═══════════════════════════════════════════════════════════
--  WAFI TIJARAH TRADING — SQL TAMBAHAN #8
--  Jalankan SEKALI sahaja dalam Supabase SQL Editor.
--  (Alamat & lokasi GPS untuk pre-order — pembeli cari lokasi kedai
--   sendiri di borang awam, guna Google Places)
-- ═══════════════════════════════════════════════════════════

ALTER TABLE pre_order ADD COLUMN IF NOT EXISTS alamat text;
ALTER TABLE pre_order ADD COLUMN IF NOT EXISTS lat float8;
ALTER TABLE pre_order ADD COLUMN IF NOT EXISTS lng float8;
