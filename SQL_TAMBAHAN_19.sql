-- ═══════════════════════════════════════════════════════════
--  WAFI TIJARAH TRADING — SQL TAMBAHAN #19
--  Jalankan SEKALI sahaja dalam Supabase SQL Editor.
--  (Simpan bandar (city) pelanggan — diisi automatik daripada poskod
--   semasa checkout, digunakan untuk label EasyParcel yang lebih tepat)
-- ═══════════════════════════════════════════════════════════

ALTER TABLE pesanan_edagang ADD COLUMN IF NOT EXISTS bandar text;
