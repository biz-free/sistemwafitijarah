-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 135: Baiki "column reference item is ambiguous" di padam_transaksi_kedai
-- (regresi susulan #106 / SQL_TAMBAHAN_134)
--
-- PUNCA: Query baharu (kira v_upah_trx) di SQL_TAMBAHAN_134 guna alias "item" utk
-- jsonb_array_elements(...) — tapi "item" JUGA nama pembolehubah plpgsql sedia ada
-- (loop var "FOR item IN SELECT * FROM jsonb_array_elements(v_trx.items) LOOP" di atas
-- dlm fungsi yg sama). Postgres tak dapat tentukan sama ada "item->>'qty'" merujuk
-- pembolehubah plpgsql atau alias jadual dlm query — RAISE "column reference item
-- is ambiguous". Setiap cubaan padam transaksi (mana2 transaksi) gagal serta-merta.
--
-- BAIKI: tukar alias jadual kepada "itm" (tak berlanggar dgn pembolehubah plpgsql
-- "item") dlm query pengiraan v_upah_trx sahaja — logik tak berubah.
-- Diuji live (BEGIN/ROLLBACK) — padam_transaksi_kedai('T7453508', 5.0) kini
-- pulangkan {"jumlah_upah":12,"jumlah_minyak":5,"jumlah_pelarasan":17,
-- "pelarasan_dicipta":true} tanpa ralat.
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.padam_transaksi_kedai(p_id text, p_kos_minyak_pulih numeric DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_trx RECORD; item jsonb; v_pekerja_id uuid; v_nama text; v_qty int;
  v_upah_trx numeric := 0; v_kedai_nama text; v_baucar_status text; v_hasil jsonb;
BEGIN
  IF NOT is_pemilik() THEN RAISE EXCEPTION 'Hanya pemilik boleh padam transaksi'; END IF;

  SELECT * INTO v_trx FROM transaksi WHERE id = p_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Transaksi tidak dijumpai'; END IF;

  BEGIN
    v_pekerja_id := v_trx.created_by::uuid;
  EXCEPTION WHEN others THEN
    v_pekerja_id := NULL;
  END;

  FOR item IN SELECT * FROM jsonb_array_elements(v_trx.items) LOOP
    v_qty := (item->>'qty')::int;
    IF v_pekerja_id IS NOT NULL THEN
      INSERT INTO stok_pekerja (pekerja_id, stok_id, kuantiti) VALUES (v_pekerja_id, item->>'stokId', v_qty)
        ON CONFLICT (pekerja_id, stok_id) DO UPDATE SET kuantiti = stok_pekerja.kuantiti + v_qty;
      SELECT nama INTO v_nama FROM stok WHERE id = item->>'stokId';
      INSERT INTO serahan_produk (id, pekerja_id, stok_id, stok_nama, kuantiti, jenis, status)
        VALUES (gen_random_uuid()::text, v_pekerja_id, item->>'stokId', COALESCE(v_nama, item->>'stokId'), v_qty, 'padam_pulang', 'disahkan');
    ELSE
      UPDATE stok SET stok = stok + v_qty WHERE id = item->>'stokId';
    END IF;
  END LOOP;

  IF v_trx.status = 'hutang' AND v_trx.kedai_id IS NOT NULL THEN
    UPDATE kedai SET hutang = GREATEST(0, hutang - v_trx.jumlah) WHERE id = v_trx.kedai_id;
  END IF;

  -- FIX: alias "item" → "itm" (elak perlanggaran dgn pembolehubah plpgsql "item" di atas).
  SELECT COALESCE(SUM((itm->>'qty')::numeric * COALESCE(s.upah_pekerja, 0)), 0) INTO v_upah_trx
    FROM jsonb_array_elements(
      CASE WHEN v_trx.kaedah_bayaran = 'consignment' AND v_trx.items_terjual IS NOT NULL
           THEN v_trx.items_terjual ELSE v_trx.items END
    ) itm
    LEFT JOIN stok s ON s.id = itm->>'stokId';

  v_hasil := jsonb_build_object('pelarasan_dicipta', false);

  IF v_pekerja_id IS NOT NULL AND (v_upah_trx > 0 OR p_kos_minyak_pulih > 0) THEN
    SELECT status INTO v_baucar_status FROM baucar_bayaran
      WHERE pekerja_id = v_pekerja_id AND kategori = 'upah_harian'
        AND tarikh = (v_trx.tarikh_masa AT TIME ZONE 'Asia/Kuala_Lumpur')::date;
    IF v_baucar_status IN ('diluluskan','dibayar') THEN
      SELECT nama INTO v_kedai_nama FROM kedai WHERE id = v_trx.kedai_id;
      INSERT INTO pelarasan_kos_pekerja (id, pekerja_id, transaksi_id, kedai_nama, sebab, jumlah_upah, jumlah_minyak, tarikh_asal, created_by)
      VALUES (gen_random_uuid()::text, v_pekerja_id, p_id, v_kedai_nama,
        'Transaksi dipadam selepas baucar diluluskan (pulangan/batal kedai)',
        v_upah_trx, GREATEST(0, p_kos_minyak_pulih),
        (v_trx.tarikh_masa AT TIME ZONE 'Asia/Kuala_Lumpur')::date, auth.uid());
      v_hasil := jsonb_build_object('pelarasan_dicipta', true, 'jumlah_upah', v_upah_trx,
        'jumlah_minyak', GREATEST(0, p_kos_minyak_pulih), 'jumlah_pelarasan', v_upah_trx + GREATEST(0, p_kos_minyak_pulih));
    END IF;
  END IF;

  DELETE FROM transaksi WHERE id = p_id;
  RETURN v_hasil;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.padam_transaksi_kedai(text, numeric) TO authenticated;
