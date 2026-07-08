-- ═══════════════════════════════════════════════════════════
--  WAFI TIJARAH TRADING — SQL TAMBAHAN #9
--  Jalankan SEKALI sahaja dalam Supabase SQL Editor.
--  (Belian peribadi, upah per-produk, status pekerja tidak aktif)
-- ═══════════════════════════════════════════════════════════

-- ═══ Rekod Baru: Belian Peribadi (tiada kedai destinasi) ═══
ALTER TABLE transaksi ADD COLUMN IF NOT EXISTS nama_pembeli text;

-- Kemaskini submit_penghantaran supaya terima nama_pembeli (kedai_id boleh NULL
-- untuk belian peribadi — UPDATE kedai di bawah automatik tak beri kesan sebab
-- "WHERE id = NULL" tidak sepadan mana-mana baris).
CREATE OR REPLACE FUNCTION submit_penghantaran(
  p_id text, p_kedai_id text, p_items jsonb, p_jumlah float,
  p_status text, p_nota text, p_resit text, p_jarak_km float DEFAULT 0,
  p_nama_pembeli text DEFAULT NULL
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

  INSERT INTO transaksi (id, kedai_id, nama_pembeli, items, jumlah, status, nota, resit, jarak_km, created_by)
  VALUES (p_id, p_kedai_id, p_nama_pembeli, p_items, p_jumlah, p_status, p_nota, p_resit, p_jarak_km, auth.uid()::text);

  UPDATE kedai SET
    hutang = hutang + (CASE WHEN p_status = 'hutang' THEN p_jumlah ELSE 0 END),
    last_visit = CURRENT_DATE::text
  WHERE id = p_kedai_id;
END;
$$;

-- ═══ Upah pekerja per-produk (gantikan kadar sejagat) ═══
ALTER TABLE stok ADD COLUMN IF NOT EXISTS upah_pekerja float DEFAULT 0;

-- ═══ Status pekerja aktif/tidak aktif (pekerja tidak aktif boleh dipadam) ═══
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'aktif';

DROP POLICY IF EXISTS "pemilik padam profil pekerja" ON profiles;
CREATE POLICY "pemilik padam profil pekerja" ON profiles FOR DELETE USING (is_pemilik());
