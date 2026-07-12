-- ═══════════════════════════════════════════════════════════
--  WAFI TIJARAH TRADING — SQL TAMBAHAN #27
--  Jalankan SEKALI sahaja dalam Supabase SQL Editor.
--  (Baucar Bayaran kategori Petrol kini secara automatik sertakan log
--   perjalanan harian (tarikh + jarak km) sebagai bukti sokongan — tak
--   perlu resit manual lagi untuk petrol, kerana jarak GPS itu sendiri
--   ialah rekod objektif yang boleh disemak.)
-- ═══════════════════════════════════════════════════════════

ALTER TABLE baucar_bayaran ADD COLUMN IF NOT EXISTS butiran jsonb;
