-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 71: Pemilik boleh pulangkan stok bawaan MANA-MANA
-- pekerja terus ke gudang (bukan hanya pekerja pulangkan stok
-- sendiri) — untuk kad "Stok Bawaan Semua Pekerja" (Tab Stok >
-- Mobile, pemilik sahaja).
--
-- pulang_stok_pekerja() sedia ada hanya guna auth.uid() (self-
-- service, 2 argumen: p_stok_id, p_qty). Function BAHARU
-- berasingan (3 argumen, ada p_pekerja_id) supaya overload tak
-- berlanggar dengan panggilan client sedia ada. Corak keselamatan
-- sama seperti pindah_stok_pekerja (pemilik sahaja, is_pemilik()).
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.pulangkan_stok_pekerja_pemilik(p_pekerja_id uuid, p_stok_id text, p_qty integer)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_nama text;
BEGIN
  IF NOT is_pemilik() THEN
    RAISE EXCEPTION 'Hanya pemilik boleh pulangkan stok bagi pihak pekerja';
  END IF;
  IF p_qty <= 0 THEN RAISE EXCEPTION 'Kuantiti mesti lebih 0'; END IF;

  UPDATE stok_pekerja SET kuantiti = kuantiti - p_qty
    WHERE pekerja_id = p_pekerja_id AND stok_id = p_stok_id AND kuantiti >= p_qty;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Stok bawaan pekerja tidak mencukupi';
  END IF;

  UPDATE stok SET stok = stok + p_qty WHERE id = p_stok_id;
  SELECT nama INTO v_nama FROM stok WHERE id = p_stok_id;
  INSERT INTO serahan_produk (id, pekerja_id, rujuk_pekerja_id, stok_id, stok_nama, kuantiti, jenis, status)
  VALUES (gen_random_uuid()::text, p_pekerja_id, auth.uid(), p_stok_id, COALESCE(v_nama, p_stok_id), p_qty, 'baik', 'disahkan');
END;
$$;
GRANT EXECUTE ON FUNCTION public.pulangkan_stok_pekerja_pemilik(uuid, text, integer) TO authenticated;
