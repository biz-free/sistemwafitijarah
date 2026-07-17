-- ═══════════════════════════════════════════════════════════
--  WAFI TIJARAH TRADING — SQL TAMBAHAN #33
--  Jalankan SEKALI sahaja dalam Supabase SQL Editor.
--  (Tambah kaedah "💳 Bayar Online" (Billplz — FPX/kad automatik) di
--   pesan.html, sama seperti index.html. Perlu deploy semula 2 Edge
--   Function sedia ada — lihat PANDUAN_SETUP.md.)
-- ═══════════════════════════════════════════════════════════

ALTER TABLE pre_order ADD COLUMN IF NOT EXISTS billplz_bill_id text;
ALTER TABLE pre_order ADD COLUMN IF NOT EXISTS status_bayaran text DEFAULT 'menunggu';

-- Kemaskini fungsi awam semak status pesanan supaya sokong DUA jenis pesanan
-- (pesanan_edagang dari index.html DAN pre_order dari pesan.html).
CREATE OR REPLACE FUNCTION semak_status_pesanan(p_id text)
RETURNS TABLE(status_bayaran text, status_pesanan text, jumlah float)
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT status_bayaran, status_pesanan, jumlah FROM pesanan_edagang WHERE id = p_id
  UNION ALL
  SELECT status_bayaran, status, jumlah_selepas_diskaun FROM pre_order WHERE id = p_id
  LIMIT 1;
$$;
