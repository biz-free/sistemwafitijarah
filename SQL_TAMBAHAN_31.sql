-- ═══════════════════════════════════════════════════════════
--  WAFI TIJARAH TRADING — SQL TAMBAHAN #31
--  Jalankan SEKALI sahaja dalam Supabase SQL Editor.
--  ("Sertai Ejen" digantikan dengan "Sertai Kami — Servis Marketing":
--   borang untuk pembekal produk yang mahu Wafi Tijarah bantu jual/
--   pasarkan produk mereka — tambah lajur nama produk, harga, margin
--   keuntungan & gambar produk pada jadual pemohon_program sedia ada.)
-- ═══════════════════════════════════════════════════════════

ALTER TABLE pemohon_program DROP CONSTRAINT IF EXISTS pemohon_program_jenis_check;
ALTER TABLE pemohon_program ADD CONSTRAINT pemohon_program_jenis_check CHECK (jenis IN ('ejen','penghantar','marketing'));

ALTER TABLE pemohon_program ADD COLUMN IF NOT EXISTS nama_produk text;
ALTER TABLE pemohon_program ADD COLUMN IF NOT EXISTS harga float;
ALTER TABLE pemohon_program ADD COLUMN IF NOT EXISTS margin_peratus float;
ALTER TABLE pemohon_program ADD COLUMN IF NOT EXISTS gambar_url text;
