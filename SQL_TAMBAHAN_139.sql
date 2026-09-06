-- SQL_TAMBAHAN_139: Tukar Produk dalam Transaksi (pemilik sahaja)
--
-- Kadang pekerja tersalah pilih produk semasa rekod penghantaran/consignment (cth
-- produk A dihantar tapi produk B yg direkod dlm app). Sebelum ni TIADA cara betulkan
-- selain padam transaksi penuh & minta pekerja hantar semula (menyusahkan, hilang
-- jejak audit asal). Fungsi ni tukar SATU baris produk dlm 1 transaksi, kekalkan
-- kuantiti, dan urus SEMUA kesan automatik:
--   • Stok bawaan pekerja: pulangkan produk LAMA, tolak produk BAHARU (rollback
--     kalau stok baharu tak cukup — elak transaksi "separuh terlaksana").
--   • items (produk+harga), items_terjual & items_pulang (consignment separa/penuh
--     disahkan) — rujukan stokId lama ditukar ke baharu di SEMUA tempat berkaitan.
--   • jumlah/jumlah_asal dikira semula (kekalkan kadar diskaun asal transaksi).
--   • kedai.hutang dilaraskan ikut beza jumlah (kalau status='hutang').
--
-- Diuji live (BEGIN/ROLLBACK) — T5091574 (S003→S001): stok bawaan pekerja betul
-- terlaras (S003 +1, S001 -1), items & items_terjual betul tukar rujukan stokId,
-- jumlah dikira semula (RM24→RM26 ikut harga produk baharu).
CREATE OR REPLACE FUNCTION public.tukar_produk_transaksi(p_transaksi_id text, p_stok_id_lama text, p_stok_id_baru text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_trx RECORD; v_pekerja_id uuid; v_qty int;
  v_harga_baru double precision; v_sub_baru double precision := 0;
  v_jumlah_baru double precision; v_jumlah_lama double precision;
  v_items_baru jsonb; v_items_terjual_baru jsonb; v_items_pulang_baru jsonb;
BEGIN
  IF NOT is_pemilik() THEN RAISE EXCEPTION 'Hanya pemilik boleh tukar produk transaksi'; END IF;
  IF p_stok_id_lama = p_stok_id_baru THEN RAISE EXCEPTION 'Produk baharu mesti berbeza drpd produk asal'; END IF;

  SELECT * INTO v_trx FROM transaksi WHERE id = p_transaksi_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Transaksi tidak dijumpai'; END IF;

  SELECT (item->>'qty')::int INTO v_qty
  FROM jsonb_array_elements(v_trx.items) item WHERE item->>'stokId' = p_stok_id_lama;
  IF v_qty IS NULL THEN RAISE EXCEPTION 'Produk % bukan sebahagian transaksi ini', p_stok_id_lama; END IF;

  SELECT harga_jual INTO v_harga_baru FROM stok WHERE id = p_stok_id_baru;
  IF v_harga_baru IS NULL THEN RAISE EXCEPTION 'Produk baharu % tidak wujud atau telah dipadam', p_stok_id_baru; END IF;

  BEGIN v_pekerja_id := v_trx.created_by::uuid; EXCEPTION WHEN others THEN v_pekerja_id := NULL; END;

  IF v_pekerja_id IS NOT NULL THEN
    INSERT INTO stok_pekerja (pekerja_id, stok_id, kuantiti) VALUES (v_pekerja_id, p_stok_id_lama, v_qty)
      ON CONFLICT (pekerja_id, stok_id) DO UPDATE SET kuantiti = stok_pekerja.kuantiti + v_qty;

    UPDATE stok_pekerja SET kuantiti = kuantiti - v_qty
      WHERE pekerja_id = v_pekerja_id AND stok_id = p_stok_id_baru AND kuantiti >= v_qty;
    IF NOT FOUND THEN
      UPDATE stok_pekerja SET kuantiti = kuantiti - v_qty WHERE pekerja_id = v_pekerja_id AND stok_id = p_stok_id_lama;
      RAISE EXCEPTION 'Stok bawaan pekerja tidak mencukupi utk produk baharu % (perlu % unit)', p_stok_id_baru, v_qty;
    END IF;
  END IF;

  SELECT jsonb_agg(
    CASE WHEN item->>'stokId' = p_stok_id_lama
      THEN item || jsonb_build_object('stokId', p_stok_id_baru, 'harga', v_harga_baru)
      ELSE item END
  ) INTO v_items_baru FROM jsonb_array_elements(v_trx.items) item;

  SELECT COALESCE(SUM(COALESCE((it->>'harga')::double precision,0) * (it->>'qty')::int),0) INTO v_sub_baru
  FROM jsonb_array_elements(v_items_baru) it;
  v_jumlah_lama := v_trx.jumlah;
  v_jumlah_baru := ROUND((v_sub_baru * (1 - COALESCE(v_trx.diskaun_peratus,0)/100))::numeric, 2);

  IF v_trx.items_terjual IS NOT NULL THEN
    SELECT COALESCE(jsonb_agg(CASE WHEN it->>'stokId'=p_stok_id_lama THEN it||jsonb_build_object('stokId',p_stok_id_baru) ELSE it END), '[]'::jsonb)
      INTO v_items_terjual_baru FROM jsonb_array_elements(v_trx.items_terjual) it;
  END IF;
  IF v_trx.items_pulang IS NOT NULL THEN
    SELECT COALESCE(jsonb_agg(CASE WHEN it->>'stokId'=p_stok_id_lama THEN it||jsonb_build_object('stokId',p_stok_id_baru) ELSE it END), '[]'::jsonb)
      INTO v_items_pulang_baru FROM jsonb_array_elements(v_trx.items_pulang) it;
  END IF;

  UPDATE transaksi SET
    items = v_items_baru,
    items_terjual = v_items_terjual_baru,
    items_pulang = v_items_pulang_baru,
    jumlah = v_jumlah_baru,
    jumlah_asal = v_sub_baru
  WHERE id = p_transaksi_id;

  IF v_trx.status = 'hutang' AND v_trx.kedai_id IS NOT NULL THEN
    UPDATE kedai SET hutang = GREATEST(0, hutang - v_jumlah_lama + v_jumlah_baru) WHERE id = v_trx.kedai_id;
  END IF;

  RETURN jsonb_build_object('qty', v_qty, 'jumlah_lama', v_jumlah_lama, 'jumlah_baru', v_jumlah_baru);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.tukar_produk_transaksi(text, text, text) TO authenticated;
