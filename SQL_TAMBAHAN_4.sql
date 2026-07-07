-- ═══════════════════════════════════════════════════════════
--  WAFI TIJARAH TRADING — SQL TAMBAHAN #4
--  Jalankan SEKALI sahaja dalam Supabase SQL Editor.
--  (Untuk ciri: QR Pre-Order di resit, gambar produk, diskaun Online Transfer)
-- ═══════════════════════════════════════════════════════════

-- ═══ Gambar produk & kaitan pre-order dengan kedai sedia ada ═══
ALTER TABLE stok ADD COLUMN IF NOT EXISTS gambar_url text;
ALTER TABLE pre_order ADD COLUMN IF NOT EXISTS kedai_id text REFERENCES kedai(id);
ALTER TABLE pre_order ADD COLUMN IF NOT EXISTS bayar_metod text DEFAULT 'cod'; -- cod / transfer
ALTER TABLE pre_order ADD COLUMN IF NOT EXISTS jumlah_asal float DEFAULT 0;
ALTER TABLE pre_order ADD COLUMN IF NOT EXISTS diskaun_peratus float DEFAULT 0;
ALTER TABLE pre_order ADD COLUMN IF NOT EXISTS jumlah_selepas_diskaun float DEFAULT 0;

-- ═══ Tetapan Pre-Order & Diskaun Online Transfer (1 baris, boleh baca umum) ═══
CREATE TABLE tetapan (
  id int PRIMARY KEY DEFAULT 1,
  minima_transfer float DEFAULT 500,
  diskaun_peratus float DEFAULT 5,
  qr_bank_url text,
  butiran_bank text,
  CONSTRAINT satu_baris_sahaja CHECK (id = 1)
);
INSERT INTO tetapan (id) VALUES (1) ON CONFLICT (id) DO NOTHING;

ALTER TABLE tetapan ENABLE ROW LEVEL SECURITY;
-- Sesiapa (termasuk borang pre-order awam) boleh baca tetapan diskaun
CREATE POLICY "semua boleh baca tetapan" ON tetapan FOR SELECT USING (true);
-- Hanya pemilik boleh kemaskini
CREATE POLICY "pemilik boleh kemaskini tetapan" ON tetapan FOR UPDATE USING (is_pemilik());

-- ═══ Fungsi awam dikemaskini — sertakan gambar_url ═══
-- NOTA: kena DROP dulu sebab bentuk pulangan (return type) berubah dari versi asal
-- (SQL_TAMBAHAN_2.sql) — Postgres tak boleh CREATE OR REPLACE bila OUT parameters berbeza.
DROP FUNCTION IF EXISTS senarai_produk_awam();
CREATE OR REPLACE FUNCTION senarai_produk_awam()
RETURNS TABLE(id text, nama text, unit text, harga_jual float, kategori text, gambar_url text)
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT id, nama, unit, harga_jual, kategori, gambar_url FROM stok ORDER BY nama;
$$;
GRANT EXECUTE ON FUNCTION senarai_produk_awam() TO anon, authenticated;

-- ═══ Fungsi awam — maklumat asas kedai (untuk prefill borang bila dibuka via QR resit) ═══
CREATE OR REPLACE FUNCTION maklumat_kedai_awam(p_id text)
RETURNS TABLE(nama text, telefon text)
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT nama, telefon FROM kedai WHERE id = p_id;
$$;
GRANT EXECUTE ON FUNCTION maklumat_kedai_awam(text) TO anon, authenticated;

-- ═══════════════════════════════════════════════════════════
--  STORAGE BUCKET untuk gambar produk & QR bank
--  Buat bucket dahulu melalui Dashboard (SQL tak boleh cipta bucket):
--    Supabase Dashboard → Storage → "New bucket"
--    Nama: produk-gambar
--    Public bucket: ON (hidupkan)
--  Lepas bucket wujud, jalankan dasar akses di bawah:
-- ═══════════════════════════════════════════════════════════
CREATE POLICY "awam boleh lihat gambar produk" ON storage.objects FOR SELECT USING (bucket_id = 'produk-gambar');
CREATE POLICY "pemilik boleh upload gambar produk" ON storage.objects FOR INSERT WITH CHECK (bucket_id = 'produk-gambar' AND is_pemilik());
CREATE POLICY "pemilik boleh kemaskini gambar produk" ON storage.objects FOR UPDATE USING (bucket_id = 'produk-gambar' AND is_pemilik());
CREATE POLICY "pemilik boleh padam gambar produk" ON storage.objects FOR DELETE USING (bucket_id = 'produk-gambar' AND is_pemilik());
