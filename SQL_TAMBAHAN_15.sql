-- ═══════════════════════════════════════════════════════════
--  WAFI TIJARAH TRADING — SQL TAMBAHAN #15
--  Jalankan SEKALI sahaja dalam Supabase SQL Editor.
--  (Fasa 3b — simpan pautan label & tracking EasyParcel selepas booking)
-- ═══════════════════════════════════════════════════════════

ALTER TABLE pesanan_edagang ADD COLUMN IF NOT EXISTS easyparcel_awb_url text;
ALTER TABLE pesanan_edagang ADD COLUMN IF NOT EXISTS easyparcel_tracking_url text;
