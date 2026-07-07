-- ═══════════════════════════════════════════════════════════
--  SAMBUNGAN SQL_TAMBAHAN_4.sql
--  Guna fail ini SAHAJA jika anda dah cuba jalankan SQL_TAMBAHAN_4.sql
--  penuh tadi dan ia berhenti pada ralat "cannot change return type".
--  (Jadual/kolum sebelum ini dah berjaya dicipta — jangan run fail asal semula.)
-- ═══════════════════════════════════════════════════════════

-- ═══ Fungsi awam dikemaskini — sertakan gambar_url ═══
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

-- ═══ Dasar akses Storage untuk bucket "produk-gambar" (pastikan bucket dah dicipta di Dashboard) ═══
CREATE POLICY "awam boleh lihat gambar produk" ON storage.objects FOR SELECT USING (bucket_id = 'produk-gambar');
CREATE POLICY "pemilik boleh upload gambar produk" ON storage.objects FOR INSERT WITH CHECK (bucket_id = 'produk-gambar' AND is_pemilik());
CREATE POLICY "pemilik boleh kemaskini gambar produk" ON storage.objects FOR UPDATE USING (bucket_id = 'produk-gambar' AND is_pemilik());
CREATE POLICY "pemilik boleh padam gambar produk" ON storage.objects FOR DELETE USING (bucket_id = 'produk-gambar' AND is_pemilik());
