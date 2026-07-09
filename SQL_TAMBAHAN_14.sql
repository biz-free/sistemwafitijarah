-- ═══════════════════════════════════════════════════════════
--  WAFI TIJARAH TRADING — SQL TAMBAHAN #14
--  Jalankan SEKALI sahaja dalam Supabase SQL Editor.
--  (Fasa 3b — Kadar Penghantaran Sebenar & Label EasyParcel)
-- ═══════════════════════════════════════════════════════════

-- ═══ Berat produk (kg) — untuk kira kos penghantaran sebenar ═══
ALTER TABLE stok ADD COLUMN IF NOT EXISTS berat float DEFAULT 0.5;

-- ═══ Alamat pengambilan (pickup) — dihantar sebagai "sender" ke EasyParcel ═══
ALTER TABLE tetapan ADD COLUMN IF NOT EXISTS pengirim_nama text DEFAULT 'Wafi Tijarah Trading';
ALTER TABLE tetapan ADD COLUMN IF NOT EXISTS pengirim_telefon text;
ALTER TABLE tetapan ADD COLUMN IF NOT EXISTS pengirim_email text;
ALTER TABLE tetapan ADD COLUMN IF NOT EXISTS pengirim_alamat text;
ALTER TABLE tetapan ADD COLUMN IF NOT EXISTS pengirim_poskod text;
ALTER TABLE tetapan ADD COLUMN IF NOT EXISTS pengirim_bandar text;
ALTER TABLE tetapan ADD COLUMN IF NOT EXISTS pengirim_negeri text;

-- ═══ Fungsi awam dikemaskini — tambah berat, KEKALKAN gambar_urls & jumlah_terjual
--     (bentuk asal dari SQL_TAMBAHAN_7.sql — jangan hilangkan bila tambah kolum baru) ═══
DROP FUNCTION IF EXISTS senarai_produk_awam();
CREATE FUNCTION senarai_produk_awam()
RETURNS TABLE(id text, nama text, unit text, harga_jual float, kategori text, gambar_url text, gambar_urls jsonb, jumlah_terjual bigint, berat float)
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT s.id, s.nama, s.unit, s.harga_jual, s.kategori, s.gambar_url, s.gambar_urls,
    COALESCE((SELECT SUM((item->>'qty')::int) FROM transaksi t, jsonb_array_elements(t.items) item WHERE item->>'stokId' = s.id), 0) AS jumlah_terjual,
    s.berat
  FROM stok s ORDER BY nama;
$$;
GRANT EXECUTE ON FUNCTION senarai_produk_awam() TO anon, authenticated;

-- ═══ Kolum tambahan pesanan — simpan kurier dipilih semasa checkout & status label ═══
ALTER TABLE pesanan_edagang ADD COLUMN IF NOT EXISTS kurier_service_id text;
ALTER TABLE pesanan_edagang ADD COLUMN IF NOT EXISTS easyparcel_status text;
-- nama_kurier & no_tracking sudah wujud sejak SQL_TAMBAHAN_11 — digunakan semula
-- untuk simpan nama kurier dipilih (semasa checkout) dan no. AWB (selepas label dijana).
