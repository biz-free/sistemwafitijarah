-- ═══════════════════════════════════════════════════════════
--  WAFI TIJARAH TRADING — SQL TAMBAHAN #16
--  Jalankan SEKALI sahaja dalam Supabase SQL Editor.
--  (Fasa 2 — Payment Gateway Billplz: bayaran online FPX/kad automatik)
-- ═══════════════════════════════════════════════════════════

ALTER TABLE pesanan_edagang ADD COLUMN IF NOT EXISTS billplz_bill_id text;

-- ═══ Fungsi awam — semak status bayaran pesanan (untuk paparan selepas
--     redirect balik dari Billplz). SENGAJA hanya pulangkan status &
--     jumlah, BUKAN alamat/telefon/emel pelanggan — supaya selamat
--     dipanggil oleh sesiapa (termasuk guest checkout tanpa akaun) yang
--     tahu ID pesanan sahaja. Status SEBENAR (bukan query param redirect
--     yang boleh dipalsukan) sebab dikemaskini oleh webhook Billplz
--     terus dalam pangkalan data. ═══
CREATE OR REPLACE FUNCTION semak_status_pesanan(p_id text)
RETURNS TABLE(status_bayaran text, status_pesanan text, jumlah float)
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT status_bayaran, status_pesanan, jumlah FROM pesanan_edagang WHERE id = p_id;
$$;
GRANT EXECUTE ON FUNCTION semak_status_pesanan(text) TO anon, authenticated;
