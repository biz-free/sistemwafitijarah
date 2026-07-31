-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 73: minta_ambil_stok terima nota pilihan (p_sebab)
-- — untuk "Request Stok Mobile" (Tab Stok > Mobile) yang benarkan
-- pekerja hantar beberapa produk sekali gus + nota tarikh/masa pick
-- up dijadualkan, disimpan dalam medan "sebab" sedia ada (tak
-- digunakan sebelum ini utk jenis 'ambil').
--
-- DROP dahulu (bukan CREATE OR REPLACE terus) sebab tambah
-- parameter baharu = signature berbeza — kalau tak drop, wujud 2
-- overload serentak (3 & 4 argumen) yang buat panggilan client
-- sedia ada (3 argumen, dari butang "📥 Ambil Stok" single-item)
-- jadi ambiguous/gagal. Fungsi asal (SQL_TAMBAHAN_5) tiada
-- p_sebab langsung.
-- ═══════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.minta_ambil_stok(text, text, integer);

CREATE OR REPLACE FUNCTION public.minta_ambil_stok(p_id text, p_stok_id text, p_qty integer, p_sebab text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_nama text; v_ada_stok int;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Log masuk diperlukan'; END IF;
  IF p_qty <= 0 THEN RAISE EXCEPTION 'Kuantiti mesti lebih 0'; END IF;
  SELECT stok, nama INTO v_ada_stok, v_nama FROM stok WHERE id = p_stok_id;
  IF v_ada_stok IS NULL THEN RAISE EXCEPTION 'Produk tidak dijumpai'; END IF;
  IF v_ada_stok < p_qty THEN RAISE EXCEPTION 'Stok gudang tidak mencukupi (baki: %)', v_ada_stok; END IF;
  INSERT INTO serahan_produk (id, pekerja_id, stok_id, stok_nama, kuantiti, jenis, status, sebab)
  VALUES (p_id, auth.uid(), p_stok_id, COALESCE(v_nama, p_stok_id), p_qty, 'ambil', 'menunggu', p_sebab);
END;
$$;
GRANT EXECUTE ON FUNCTION public.minta_ambil_stok(text, text, integer, text) TO authenticated;
