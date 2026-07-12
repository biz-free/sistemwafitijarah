-- ═══════════════════════════════════════════════════════════
--  WAFI TIJARAH TRADING — SQL TAMBAHAN #26
--  Jalankan SEKALI sahaja dalam Supabase SQL Editor.
--  (1) Galeri gambar kedai — snap gambar depan kedai semasa daftar/lawatan.
--  (2) Baucar Bayaran — rekod audit rasmi bernombor siri untuk upah,
--      petrol & duit makan yang sudah dikira secara automatik dalam Laporan.
-- ═══════════════════════════════════════════════════════════

-- ═══ (1) Galeri Gambar Kedai ═══
ALTER TABLE kedai ADD COLUMN IF NOT EXISTS gambar_urls jsonb DEFAULT '[]';

-- Storan: buat bucket "kedai-gambar" dalam Supabase Dashboard → Storage → New bucket
-- Nama: kedai-gambar · Public bucket: ON (sama macam produk-gambar, gambar depan kedai tidak sensitif)
CREATE POLICY "awam boleh lihat gambar kedai" ON storage.objects FOR SELECT USING (bucket_id = 'kedai-gambar');
CREATE POLICY "staff boleh upload gambar kedai" ON storage.objects FOR INSERT WITH CHECK (bucket_id = 'kedai-gambar' AND auth.role() = 'authenticated');
CREATE POLICY "staff boleh padam gambar kedai" ON storage.objects FOR DELETE USING (bucket_id = 'kedai-gambar' AND auth.role() = 'authenticated');

-- ═══ (2) Baucar Bayaran (Payment Voucher) — satu baucar setiap pekerja/kategori/bulan ═══
CREATE SEQUENCE IF NOT EXISTS baucar_siri_seq;

CREATE TABLE IF NOT EXISTS baucar_bayaran (
  id text PRIMARY KEY,
  no_siri text UNIQUE NOT NULL,
  pekerja_id uuid REFERENCES auth.users(id),
  kategori text NOT NULL CHECK (kategori IN ('petrol','upah','makan')),
  bulan text NOT NULL, -- '2026-07'
  jumlah float NOT NULL DEFAULT 0,
  tujuan text,
  resit_url text,
  status text NOT NULL DEFAULT 'draf' CHECK (status IN ('draf','diluluskan','dibayar')),
  diluluskan_oleh uuid REFERENCES auth.users(id),
  diluluskan_pada timestamptz,
  dibayar_pada timestamptz,
  created_at timestamptz DEFAULT now(),
  UNIQUE(pekerja_id, kategori, bulan)
);
ALTER TABLE baucar_bayaran ENABLE ROW LEVEL SECURITY;
CREATE POLICY "pemilik urus semua baucar" ON baucar_bayaran FOR ALL USING (is_pemilik()) WITH CHECK (is_pemilik());
CREATE POLICY "pekerja baca baucar sendiri" ON baucar_bayaran FOR SELECT USING (pekerja_id = auth.uid());

-- Cipta/kemaskini baucar draf — pemilik sahaja. Guna semula jumlah yang sama seperti
-- dipaparkan dalam Laporan (kosUpah/kosMinyak/kosMakan setiap pekerja), tiada pengiraan baharu.
CREATE OR REPLACE FUNCTION cipta_baucar_bayaran(p_pekerja_id uuid, p_kategori text, p_bulan text, p_jumlah float, p_tujuan text DEFAULT NULL)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_no_siri text; v_id text; v_sedia_id text;
BEGIN
  IF NOT is_pemilik() THEN
    RAISE EXCEPTION 'Hanya pemilik boleh jana baucar bayaran';
  END IF;

  SELECT id INTO v_sedia_id FROM baucar_bayaran
    WHERE pekerja_id = p_pekerja_id AND kategori = p_kategori AND bulan = p_bulan;

  IF v_sedia_id IS NOT NULL THEN
    UPDATE baucar_bayaran SET jumlah = p_jumlah, tujuan = COALESCE(p_tujuan, tujuan)
      WHERE id = v_sedia_id AND status = 'draf'; -- baucar diluluskan/dibayar dikekalkan, tak ditimpa
    RETURN v_sedia_id;
  END IF;

  v_id := gen_random_uuid()::text;
  v_no_siri := 'PV-' || extract(year from now())::text || '-' || lpad(nextval('baucar_siri_seq')::text, 4, '0');
  INSERT INTO baucar_bayaran (id, no_siri, pekerja_id, kategori, bulan, jumlah, tujuan)
  VALUES (v_id, v_no_siri, p_pekerja_id, p_kategori, p_bulan, p_jumlah, p_tujuan);
  RETURN v_id;
END;
$$;
GRANT EXECUTE ON FUNCTION cipta_baucar_bayaran(uuid, text, text, float, text) TO authenticated;

-- Storan: buat bucket "baucar-resit" dalam Supabase Dashboard → Storage → New bucket
-- Nama: baucar-resit · Public bucket: OFF (data kewangan sensitif, sama macam bukti-bayaran)
CREATE POLICY "staff boleh upload resit baucar" ON storage.objects FOR INSERT WITH CHECK (bucket_id = 'baucar-resit' AND auth.role() = 'authenticated');
CREATE POLICY "staff boleh lihat resit baucar" ON storage.objects FOR SELECT USING (bucket_id = 'baucar-resit' AND auth.role() = 'authenticated');
