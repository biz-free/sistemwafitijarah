-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 60: Pindah stok bawaan terus antara pekerja
-- (pemilik sahaja) — tanpa perlu lalu semula ke stok gudang.
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION pindah_stok_pekerja(
  p_dari_pekerja_id uuid, p_kepada_pekerja_id uuid, p_stok_id text, p_qty int
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
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
END;
$$;
GRANT EXECUTE ON FUNCTION pindah_stok_pekerja(uuid, uuid, text, int) TO authenticated;
