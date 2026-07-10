-- ═══════════════════════════════════════════════════════════
--  WAFI TIJARAH TRADING — SQL TAMBAHAN #23
--  Jalankan SEKALI sahaja dalam Supabase SQL Editor.
--  (Pelupusan Stok — pekerja rekod stok bawaan yang rosak/expired/hilang
--   terus dari tab Penghantaran, potong stok bawaan secara automatik.)
-- ═══════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS pelupusan_stok (
  id text PRIMARY KEY,
  pekerja_id uuid REFERENCES auth.users(id),
  stok_id text REFERENCES stok(id),
  kuantiti int NOT NULL,
  sebab text NOT NULL DEFAULT 'rosak', -- rosak / expired / hilang / lain
  nota text,
  kos float DEFAULT 0, -- anggaran kerugian (harga_beli × kuantiti masa itu, kekal walau harga_beli berubah kemudian)
  created_at timestamptz DEFAULT now()
);
ALTER TABLE pelupusan_stok ENABLE ROW LEVEL SECURITY;
CREATE POLICY "pekerja urus pelupusan sendiri" ON pelupusan_stok FOR ALL USING (pekerja_id = auth.uid()) WITH CHECK (pekerja_id = auth.uid());
CREATE POLICY "pemilik baca semua pelupusan" ON pelupusan_stok FOR SELECT USING (is_pemilik());
CREATE POLICY "pemilik padam pelupusan" ON pelupusan_stok FOR DELETE USING (is_pemilik());

-- Rekod pelupusan stok bawaan (rosak/expired/hilang) — atomik: potong stok bawaan + rekod sebab & kos
CREATE OR REPLACE FUNCTION lupus_stok_pekerja(p_items jsonb, p_sebab text, p_nota text DEFAULT NULL) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE item jsonb; v_harga_beli float; v_qty int;
BEGIN
  FOR item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_qty := (item->>'qty')::int;
    IF v_qty <= 0 THEN RAISE EXCEPTION 'Kuantiti mesti lebih 0'; END IF;
    UPDATE stok_pekerja SET kuantiti = kuantiti - v_qty
      WHERE pekerja_id = auth.uid() AND stok_id = item->>'stokId' AND kuantiti >= v_qty;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Stok bawaan anda tidak mencukupi untuk %', item->>'stokId';
    END IF;
    SELECT harga_beli INTO v_harga_beli FROM stok WHERE id = item->>'stokId';
    INSERT INTO pelupusan_stok (id, pekerja_id, stok_id, kuantiti, sebab, nota, kos)
      VALUES (gen_random_uuid()::text, auth.uid(), item->>'stokId', v_qty, p_sebab, p_nota, COALESCE(v_harga_beli,0)*v_qty);
  END LOOP;
END;
$$;
GRANT EXECUTE ON FUNCTION lupus_stok_pekerja(jsonb, text, text) TO authenticated;
