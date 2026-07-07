-- ═══════════════════════════════════════════════════════════
--  WAFI TIJARAH TRADING — SQL TAMBAHAN #5
--  Jalankan SEKALI sahaja dalam Supabase SQL Editor.
--  (Stok ikut pekerja, tugasan pre-order, cuti/status pekerja,
--   profil sendiri, bukti bayaran transfer, jarak auto-GPS)
-- ═══════════════════════════════════════════════════════════

-- ═══ Pre-Order: tugasan pekerja & bukti bayaran transfer ═══
ALTER TABLE pre_order ADD COLUMN IF NOT EXISTS assigned_pekerja_id uuid REFERENCES auth.users(id);
ALTER TABLE pre_order ADD COLUMN IF NOT EXISTS bayar_tarikh date;
ALTER TABLE pre_order ADD COLUMN IF NOT EXISTS bayar_masa text;
ALTER TABLE pre_order ADD COLUMN IF NOT EXISTS bukti_bayaran_url text;

-- Kemaskini dasar baca pre_order: pekerja hanya nampak yang belum ditugaskan
-- ATAU ditugaskan kepada dirinya; pemilik nampak semua.
DROP POLICY IF EXISTS "staff boleh baca pre-order" ON pre_order;
CREATE POLICY "staff boleh baca pre-order" ON pre_order FOR SELECT USING (
  is_pemilik() OR assigned_pekerja_id IS NULL OR assigned_pekerja_id = auth.uid()
);

-- ═══ Stok ikut Pekerja (bawaan luar gudang) ═══
CREATE TABLE stok_pekerja (
  id bigserial PRIMARY KEY,
  pekerja_id uuid REFERENCES auth.users(id),
  stok_id text REFERENCES stok(id),
  kuantiti int DEFAULT 0,
  UNIQUE(pekerja_id, stok_id)
);
ALTER TABLE stok_pekerja ENABLE ROW LEVEL SECURITY;
CREATE POLICY "pekerja baca stok sendiri" ON stok_pekerja FOR SELECT USING (pekerja_id = auth.uid() OR is_pemilik());

-- Fungsi: pekerja ambil stok dari gudang (self-service, tiada kelulusan)
CREATE OR REPLACE FUNCTION ambil_stok_pekerja(p_stok_id text, p_qty int) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_qty <= 0 THEN RAISE EXCEPTION 'Kuantiti mesti lebih 0'; END IF;
  UPDATE stok SET stok = stok - p_qty WHERE id = p_stok_id AND stok >= p_qty;
  IF NOT FOUND THEN RAISE EXCEPTION 'Stok gudang tidak mencukupi'; END IF;
  INSERT INTO stok_pekerja (pekerja_id, stok_id, kuantiti) VALUES (auth.uid(), p_stok_id, p_qty)
    ON CONFLICT (pekerja_id, stok_id) DO UPDATE SET kuantiti = stok_pekerja.kuantiti + p_qty;
END;
$$;
GRANT EXECUTE ON FUNCTION ambil_stok_pekerja(text, int) TO authenticated;

-- Fungsi: pekerja pulangkan stok bawaan balik ke gudang
CREATE OR REPLACE FUNCTION pulang_stok_pekerja(p_stok_id text, p_qty int) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_qty <= 0 THEN RAISE EXCEPTION 'Kuantiti mesti lebih 0'; END IF;
  UPDATE stok_pekerja SET kuantiti = kuantiti - p_qty WHERE pekerja_id = auth.uid() AND stok_id = p_stok_id AND kuantiti >= p_qty;
  IF NOT FOUND THEN RAISE EXCEPTION 'Stok bawaan anda tidak mencukupi'; END IF;
  UPDATE stok SET stok = stok + p_qty WHERE id = p_stok_id;
END;
$$;
GRANT EXECUTE ON FUNCTION pulang_stok_pekerja(text, int) TO authenticated;

-- Kemaskini submit_penghantaran: potong dari stok BAWAAN pekerja (bukan gudang terus),
-- sebab gudang dah ditolak semasa pekerja "ambil stok" tadi.
CREATE OR REPLACE FUNCTION submit_penghantaran(
  p_id text, p_kedai_id text, p_items jsonb, p_jumlah float,
  p_status text, p_nota text, p_resit text, p_jarak_km float DEFAULT 0
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE item jsonb;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid()) THEN
    RAISE EXCEPTION 'Tidak dibenarkan';
  END IF;

  FOR item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    UPDATE stok_pekerja SET kuantiti = kuantiti - (item->>'qty')::int
      WHERE pekerja_id = auth.uid() AND stok_id = item->>'stokId' AND kuantiti >= (item->>'qty')::int;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Stok bawaan anda tidak mencukupi untuk %', item->>'stokId';
    END IF;
  END LOOP;

  INSERT INTO transaksi (id, kedai_id, items, jumlah, status, nota, resit, jarak_km, created_by)
  VALUES (p_id, p_kedai_id, p_items, p_jumlah, p_status, p_nota, p_resit, p_jarak_km, auth.uid()::text);

  UPDATE kedai SET
    hutang = hutang + (CASE WHEN p_status = 'hutang' THEN p_jumlah ELSE 0 END),
    last_visit = CURRENT_DATE::text
  WHERE id = p_kedai_id;
END;
$$;

-- ═══ Kedai: benarkan PEKERJA juga daftar kedai baru (bukan pemilik sahaja) ═══
DROP POLICY IF EXISTS "pemilik tambah kedai" ON kedai;
CREATE POLICY "staff tambah kedai" ON kedai FOR INSERT WITH CHECK (auth.role() = 'authenticated');

-- ═══ Permohonan Cuti / MC / Off ═══
CREATE TABLE permohonan_cuti (
  id text PRIMARY KEY,
  pekerja_id uuid REFERENCES auth.users(id),
  jenis text NOT NULL, -- cuti / mc / off
  tarikh_mula date NOT NULL,
  tarikh_tamat date NOT NULL,
  nota text,
  status text DEFAULT 'menunggu', -- menunggu / diluluskan / ditolak
  created_at timestamptz DEFAULT now()
);
ALTER TABLE permohonan_cuti ENABLE ROW LEVEL SECURITY;
CREATE POLICY "pekerja urus permohonan sendiri" ON permohonan_cuti FOR ALL USING (pekerja_id = auth.uid()) WITH CHECK (pekerja_id = auth.uid());
CREATE POLICY "pemilik baca semua permohonan" ON permohonan_cuti FOR SELECT USING (is_pemilik());
CREATE POLICY "pemilik kelulusan permohonan" ON permohonan_cuti FOR UPDATE USING (is_pemilik());

-- ═══ Profil: kemaskini nama/telefon sendiri (tanpa dedah medan role) ═══
CREATE OR REPLACE FUNCTION kemaskini_profil_sendiri(p_nama text, p_telefon text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE profiles SET nama = p_nama, telefon = p_telefon WHERE id = auth.uid();
END;
$$;
GRANT EXECUTE ON FUNCTION kemaskini_profil_sendiri(text, text) TO authenticated;

-- ═══════════════════════════════════════════════════════════
--  STORAGE BUCKET untuk bukti pindahan bank (SULIT — bukan public)
--  Cipta dahulu melalui Dashboard:
--    Supabase Dashboard → Storage → "New bucket"
--    Nama: bukti-bayaran
--    Public bucket: OFF (jangan hidupkan — ini data sensitif)
--  Lepas bucket wujud, jalankan dasar di bawah:
-- ═══════════════════════════════════════════════════════════
CREATE POLICY "sesiapa boleh upload bukti bayaran" ON storage.objects FOR INSERT WITH CHECK (bucket_id = 'bukti-bayaran');
CREATE POLICY "staff boleh lihat bukti bayaran" ON storage.objects FOR SELECT USING (bucket_id = 'bukti-bayaran' AND auth.role() = 'authenticated');
