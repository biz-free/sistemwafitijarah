-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 83: Button "Pindah ke Pekerja" (Tab Stok > Gudang, pemilik
-- sahaja) — pindah stok gudang terus ke bawaan PEKERJA LAIN yang dipilih,
-- auto-lulus (tiada perlu tunggu pekerja mohon dahulu via minta_ambil_stok).
--
-- Guna semula RPC ambil_stok_pekerja sedia ada (asalnya cuma utk pemilik
-- ambil ke bag SENDIRI) — tambah p_pekerja_id_override, sama corak dgn
-- submit_penghantaran/lupus_stok_pekerja/tukar_stok_expired_kedai.
-- ═══════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.ambil_stok_pekerja(text, integer);

CREATE OR REPLACE FUNCTION public.ambil_stok_pekerja(p_stok_id text, p_qty integer, p_pekerja_id_override uuid DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE v_nama text; v_pekerja_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Log masuk diperlukan'; END IF;
  IF p_qty <= 0 THEN RAISE EXCEPTION 'Kuantiti mesti lebih 0'; END IF;

  v_pekerja_id := CASE WHEN p_pekerja_id_override IS NOT NULL AND is_pemilik() THEN p_pekerja_id_override ELSE auth.uid() END;

  UPDATE stok SET stok = stok - p_qty WHERE id = p_stok_id AND stok >= p_qty;
  IF NOT FOUND THEN RAISE EXCEPTION 'Stok gudang tidak mencukupi'; END IF;
  INSERT INTO stok_pekerja (pekerja_id, stok_id, kuantiti) VALUES (v_pekerja_id, p_stok_id, p_qty)
    ON CONFLICT (pekerja_id, stok_id) DO UPDATE SET kuantiti = stok_pekerja.kuantiti + p_qty;
  SELECT nama INTO v_nama FROM stok WHERE id = p_stok_id;
  INSERT INTO serahan_produk (id, pekerja_id, stok_id, stok_nama, kuantiti, jenis, status, disahkan_oleh, disahkan_pada)
  VALUES (gen_random_uuid()::text, v_pekerja_id, p_stok_id, COALESCE(v_nama, p_stok_id), p_qty, 'ambil', 'disahkan', auth.uid(), now());
END;
$function$;
