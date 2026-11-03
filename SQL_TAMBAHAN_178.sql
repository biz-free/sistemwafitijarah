-- DILAKSANA pada projek Wafi 3 Nov 2026 (kelulusan Amirul).
-- SQL_TAMBAHAN_178: Pengalaman pembeli selepas tempahan.
-- (a) Lajur penanda supaya emel pengesahan / penghantaran tak dihantar dua kali.
-- (b) jejak_pesanan_awam() kini turut jumpa pesanan kedai (pre_order, ID PO...) —
--     supaya pautan "semak status" dari pesan.html berfungsi. Tiada telefon/emel/
--     alamat dipulangkan (sama seperti asal). Jenis lajur pulangan KEKAL sama.
ALTER TABLE pesanan_edagang ADD COLUMN IF NOT EXISTS emel_pengesahan_dihantar timestamptz;
ALTER TABLE pesanan_edagang ADD COLUMN IF NOT EXISTS emel_penghantaran_dihantar timestamptz;

CREATE OR REPLACE FUNCTION jejak_pesanan_awam(p_id text)
RETURNS TABLE(
  id text, status_pesanan text, status_bayaran text, items jsonb, jumlah float,
  nama_kurier text, no_tracking text, easyparcel_tracking_url text, easyparcel_status text,
  created_at timestamptz
)
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT id, status_pesanan, status_bayaran, items, jumlah, nama_kurier, no_tracking, easyparcel_tracking_url, easyparcel_status, created_at
  FROM pesanan_edagang WHERE id = p_id
  UNION ALL
  SELECT id, status, status_bayaran, items, jumlah_selepas_diskaun, NULL, NULL, NULL, NULL, created_at
  FROM pre_order WHERE id = p_id
  LIMIT 1;
$$;
GRANT EXECUTE ON FUNCTION jejak_pesanan_awam(text) TO anon, authenticated;
