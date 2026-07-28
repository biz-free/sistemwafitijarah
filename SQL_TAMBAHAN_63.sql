-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 63: Luaskan serahan_produk jadi log pergerakan stok
-- MENYELURUH (ambil dari gudang, pindah antara pekerja, restock
-- gudang — bukan cuma pulangan/reject sahaja) — untuk Sejarah
-- Pindahan Stok di Tab Stok > Mobile & Tab Stok > Gudang.
--
-- NOTA PENTING: sejarah ini HANYA bermula dari titik ini ke depan.
-- ambil_stok_pekerja/pindah_stok_pekerja/restock_produk TIDAK PERNAH
-- direkod sebelum ini (tiada jadual log wujud) — jadi pergerakan lama
-- sebelum migration ini TIDAK dapat dibina semula secara tepat.
-- ═══════════════════════════════════════════════════════════

ALTER TABLE serahan_produk DROP CONSTRAINT serahan_produk_jenis_check;
ALTER TABLE serahan_produk ADD CONSTRAINT serahan_produk_jenis_check
  CHECK (jenis IN ('baik','reject','ambil','pindah_keluar','pindah_masuk','restock'));
ALTER TABLE serahan_produk ADD COLUMN rujuk_pekerja_id uuid REFERENCES auth.users(id);
COMMENT ON TABLE serahan_produk IS 'Log pergerakan stok menyeluruh: ambil (gudang->pekerja), baik/pulang (pekerja->gudang), pindah_keluar/pindah_masuk (pekerja->pekerja), reject (pekerja->writeoff, perlu kelulusan pemilik), restock (tambah stok gudang). Nama jadual kekal "serahan_produk" untuk elak churn kod, skop sebenar lebih luas.';

-- ambil_stok_pekerja: log jenis='ambil', auto-disahkan (tiada kelulusan diperlukan,
-- sama macam sedia ada — sekadar tambah audit trail).
CREATE OR REPLACE FUNCTION public.ambil_stok_pekerja(p_stok_id text, p_qty int) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_nama text;
BEGIN
  IF p_qty <= 0 THEN RAISE EXCEPTION 'Kuantiti mesti lebih 0'; END IF;
  UPDATE stok SET stok = stok - p_qty WHERE id = p_stok_id AND stok >= p_qty;
  IF NOT FOUND THEN RAISE EXCEPTION 'Stok gudang tidak mencukupi'; END IF;
  INSERT INTO stok_pekerja (pekerja_id, stok_id, kuantiti) VALUES (auth.uid(), p_stok_id, p_qty)
    ON CONFLICT (pekerja_id, stok_id) DO UPDATE SET kuantiti = stok_pekerja.kuantiti + p_qty;
  SELECT nama INTO v_nama FROM stok WHERE id = p_stok_id;
  INSERT INTO serahan_produk (id, pekerja_id, stok_id, stok_nama, kuantiti, jenis, status)
  VALUES (gen_random_uuid()::text, auth.uid(), p_stok_id, COALESCE(v_nama, p_stok_id), p_qty, 'ambil', 'disahkan');
END;
$$;
GRANT EXECUTE ON FUNCTION public.ambil_stok_pekerja(text, int) TO authenticated;

-- pindah_stok_pekerja: log 2 baris (keluar utk sumber, masuk utk destinasi) supaya
-- kekal boleh papar dari perspektif MANA-MANA pekerja yang terlibat.
CREATE OR REPLACE FUNCTION public.pindah_stok_pekerja(
  p_dari_pekerja_id uuid, p_kepada_pekerja_id uuid, p_stok_id text, p_qty int
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_nama text;
BEGIN
  IF NOT is_pemilik() THEN
    RAISE EXCEPTION 'Hanya pemilik boleh pindahkan stok bawaan pekerja';
  END IF;
  IF p_qty <= 0 THEN RAISE EXCEPTION 'Kuantiti mesti lebih 0'; END IF;
  IF p_dari_pekerja_id = p_kepada_pekerja_id THEN
    RAISE EXCEPTION 'Pekerja sumber dan destinasi mesti berbeza';
  END IF;

  UPDATE stok_pekerja SET kuantiti = kuantiti - p_qty
    WHERE pekerja_id = p_dari_pekerja_id AND stok_id = p_stok_id AND kuantiti >= p_qty;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Stok bawaan pekerja sumber tidak mencukupi';
  END IF;

  INSERT INTO stok_pekerja (pekerja_id, stok_id, kuantiti) VALUES (p_kepada_pekerja_id, p_stok_id, p_qty)
    ON CONFLICT (pekerja_id, stok_id) DO UPDATE SET kuantiti = stok_pekerja.kuantiti + p_qty;

  SELECT nama INTO v_nama FROM stok WHERE id = p_stok_id;
  INSERT INTO serahan_produk (id, pekerja_id, rujuk_pekerja_id, stok_id, stok_nama, kuantiti, jenis, status)
  VALUES (gen_random_uuid()::text, p_dari_pekerja_id, p_kepada_pekerja_id, p_stok_id, COALESCE(v_nama, p_stok_id), p_qty, 'pindah_keluar', 'disahkan');
  INSERT INTO serahan_produk (id, pekerja_id, rujuk_pekerja_id, stok_id, stok_nama, kuantiti, jenis, status)
  VALUES (gen_random_uuid()::text, p_kepada_pekerja_id, p_dari_pekerja_id, p_stok_id, COALESCE(v_nama, p_stok_id), p_qty, 'pindah_masuk', 'disahkan');
END;
$$;
GRANT EXECUTE ON FUNCTION public.pindah_stok_pekerja(uuid, uuid, text, int) TO authenticated;

-- restock_produk: log jenis='restock' (pekerja_id = pemilik yang buat restock).
CREATE OR REPLACE FUNCTION public.restock_produk(p_id text, p_qty int) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_nama text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'pemilik') THEN
    RAISE EXCEPTION 'Hanya pemilik boleh restock';
  END IF;
  UPDATE stok SET stok = stok + p_qty WHERE id = p_id;
  SELECT nama INTO v_nama FROM stok WHERE id = p_id;
  INSERT INTO serahan_produk (id, pekerja_id, stok_id, stok_nama, kuantiti, jenis, status)
  VALUES (gen_random_uuid()::text, auth.uid(), p_id, COALESCE(v_nama, p_id), p_qty, 'restock', 'disahkan');
END;
$$;
GRANT EXECUTE ON FUNCTION public.restock_produk(text, int) TO authenticated;
