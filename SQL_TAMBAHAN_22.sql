-- ═══════════════════════════════════════════════════════════
--  WAFI TIJARAH TRADING — SQL TAMBAHAN #22
--  Jalankan SEKALI sahaja dalam Supabase SQL Editor.
--  (Rekod siapa daftarkan setiap kedai — untuk bonus "kedai baru"
--   dalam Kiraan Upah & paparan di Senarai Kedai.)
-- ═══════════════════════════════════════════════════════════

ALTER TABLE kedai ADD COLUMN IF NOT EXISTS didaftarkan_oleh uuid REFERENCES auth.users(id);
