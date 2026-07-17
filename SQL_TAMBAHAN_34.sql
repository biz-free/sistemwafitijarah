-- ═══════════════════════════════════════════════════════════
--  WAFI TIJARAH TRADING — SQL TAMBAHAN #34
--  Jalankan SEKALI sahaja dalam Supabase SQL Editor.
--  (Jejak Pesanan — ikon baharu di header index.html, pelanggan
--   masukkan nombor pesanan sahaja untuk lihat status & tracking
--   kurier. Fungsi ni sengaja TAK pulangkan telefon/emel/alamat
--   pelanggan — sama macam semak_status_pesanan sedia ada.)
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION jejak_pesanan_awam(p_id text)
RETURNS TABLE(
  id text, status_pesanan text, status_bayaran text, items jsonb, jumlah float,
  nama_kurier text, no_tracking text, easyparcel_tracking_url text, easyparcel_status text,
  created_at timestamptz
)
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT id, status_pesanan, status_bayaran, items, jumlah, nama_kurier, no_tracking, easyparcel_tracking_url, easyparcel_status, created_at
  FROM pesanan_edagang WHERE id = p_id;
$$;
GRANT EXECUTE ON FUNCTION jejak_pesanan_awam(text) TO anon, authenticated;
