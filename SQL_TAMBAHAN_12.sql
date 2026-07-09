-- ═══════════════════════════════════════════════════════════
--  WAFI TIJARAH TRADING — SQL TAMBAHAN #12
--  Jalankan SEKALI sahaja dalam Supabase SQL Editor.
--  (Baiki: bukti bayaran e-dagang tak disimpan; sokong paparan
--   urus pesanan e-dagang dalam pengurusan.html)
-- ═══════════════════════════════════════════════════════════

ALTER TABLE pesanan_edagang ADD COLUMN IF NOT EXISTS bukti_bayaran_url text;
ALTER TABLE pesanan_edagang ADD COLUMN IF NOT EXISTS bayar_tarikh date;
ALTER TABLE pesanan_edagang ADD COLUMN IF NOT EXISTS bayar_masa time;
