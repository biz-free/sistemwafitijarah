-- SQL_TAMBAHAN_141: Tukar Produk Transaksi — reset pengesahan consignment bila
-- produk ditukar (susulan #115/#117, bug ditemui pemilik guna sendiri live —
-- T5091574 S003→sachet kecil 20 unit).
--
-- PUNCA: tukar_produk_transaksi() sebelum ni cuma "remap" stokId dlm
-- items_terjual/items_pulang (kekalkan qty & jualan_disahkan asal) — logik ni
-- munasabah utk kes qty/produk serupa (cth betulkan 1 unit produk A→B, "1 unit
-- terjual" tu masih sah cuma produk lain). TAPI bila produk ditukar KEPADA produk
-- lain sepenuhnya dgn qty jauh berbeza (cth 1 unit S003 → 20 unit sachet kecil),
-- jualan_disahkan=true LAMA terbawa sekali → seksyen "🤝 Follow-up" (perlu
-- !jualan_disahkan) TERUS TAK MUNCUL dlm app, walhal produk/kuantiti baharu tu
-- belum pernah disahkan terjual/pulang langsung.
--
-- BAIKI: bila transaksi kaedah_bayaran='consignment', SENTIASA reset
-- jualan_disahkan=false + items_terjual/items_pulang=NULL selepas tukar produk —
-- paksa pengesahan SEGAR (Follow-up) utk produk/kuantiti baharu, tak kira apa
-- status pengesahan sebelum ni. Pengesahan qty lama (v_qty_baru < terjual+pulang
-- sedia) turut dibuang sebab dah tak relevan (semua di-reset kosong lagipun).
--
-- Diuji live (BEGIN/ROLLBACK, transaksi ujian consignment jualan_disahkan=true) —
-- selepas tukar produk, jualan_disahkan betul reset ke false, items_terjual/
-- items_pulang betul reset ke null, jumlah dikira semula tepat.
--
-- Turut betulkan T5091574 SEDIA ADA yg terjejas (jualan_disahkan direset ke false
-- terus di database, produk/kuantiti tak berubah) — supaya Follow-up terus boleh
-- diguna oleh Aremier/pemilik.
CREATE OR REPLACE FUNCTION public.tukar_produk_transaksi(
  p_transaksi_id text, p_stok_id_lama text, p_stok_id_baru text,
  p_qty_baru int DEFAULT NULL, p_pekerja_id_baru uuid DEFAULT NULL
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_trx RECORD; v_pekerja_asal uuid; v_pekerja_sasaran uuid;
  v_qty_lama int; v_qty_baru int;
  v_harga_baru double precision; v_sub_baru double precision := 0;
  v_jumlah_baru double precision; v_jumlah_lama double precision;
  v_items_baru jsonb;
  v_reset_consignment boolean;
BEGIN
  IF NOT is_pemilik() THEN RAISE EXCEPTION 'Hanya pemilik boleh tukar produk transaksi'; END IF;
  IF p_stok_id_lama = p_stok_id_baru THEN RAISE EXCEPTION 'Produk baharu mesti berbeza drpd produk asal'; END IF;

  SELECT * INTO v_trx FROM transaksi WHERE id = p_transaksi_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Transaksi tidak dijumpai'; END IF;

  SELECT (item->>'qty')::int INTO v_qty_lama
  FROM jsonb_array_elements(v_trx.items) item WHERE item->>'stokId' = p_stok_id_lama;
  IF v_qty_lama IS NULL THEN RAISE EXCEPTION 'Produk % bukan sebahagian transaksi ini', p_stok_id_lama; END IF;

  v_qty_baru := COALESCE(p_qty_baru, v_qty_lama);
  IF v_qty_baru <= 0 THEN RAISE EXCEPTION 'Kuantiti mesti lebih 0'; END IF;

  SELECT harga_jual INTO v_harga_baru FROM stok WHERE id = p_stok_id_baru;
  IF v_harga_baru IS NULL THEN RAISE EXCEPTION 'Produk baharu % tidak wujud atau telah dipadam', p_stok_id_baru; END IF;

  BEGIN v_pekerja_asal := v_trx.created_by::uuid; EXCEPTION WHEN others THEN v_pekerja_asal := NULL; END;
  v_pekerja_sasaran := COALESCE(p_pekerja_id_baru, v_pekerja_asal);

  IF v_pekerja_asal IS NOT NULL THEN
    INSERT INTO stok_pekerja (pekerja_id, stok_id, kuantiti) VALUES (v_pekerja_asal, p_stok_id_lama, v_qty_lama)
      ON CONFLICT (pekerja_id, stok_id) DO UPDATE SET kuantiti = stok_pekerja.kuantiti + v_qty_lama;
  END IF;

  IF v_pekerja_sasaran IS NOT NULL THEN
    UPDATE stok_pekerja SET kuantiti = kuantiti - v_qty_baru
      WHERE pekerja_id = v_pekerja_sasaran AND stok_id = p_stok_id_baru AND kuantiti >= v_qty_baru;
    IF NOT FOUND THEN
      IF v_pekerja_asal IS NOT NULL THEN
        UPDATE stok_pekerja SET kuantiti = kuantiti - v_qty_lama WHERE pekerja_id = v_pekerja_asal AND stok_id = p_stok_id_lama;
      END IF;
      RAISE EXCEPTION 'Stok bawaan pekerja sasaran tidak mencukupi utk produk baharu % (perlu % unit)', p_stok_id_baru, v_qty_baru;
    END IF;
  END IF;

  SELECT jsonb_agg(
    CASE WHEN item->>'stokId' = p_stok_id_lama
      THEN item || jsonb_build_object('stokId', p_stok_id_baru, 'harga', v_harga_baru, 'qty', v_qty_baru)
      ELSE item END
  ) INTO v_items_baru FROM jsonb_array_elements(v_trx.items) item;

  SELECT COALESCE(SUM(COALESCE((it->>'harga')::double precision,0) * (it->>'qty')::int),0) INTO v_sub_baru
  FROM jsonb_array_elements(v_items_baru) it;
  v_jumlah_lama := v_trx.jumlah;
  v_jumlah_baru := ROUND((v_sub_baru * (1 - COALESCE(v_trx.diskaun_peratus,0)/100))::numeric, 2);

  v_reset_consignment := v_trx.kaedah_bayaran = 'consignment';

  UPDATE transaksi SET
    items = v_items_baru,
    items_terjual = CASE WHEN v_reset_consignment THEN NULL ELSE items_terjual END,
    items_pulang = CASE WHEN v_reset_consignment THEN NULL ELSE items_pulang END,
    jualan_disahkan = CASE WHEN v_reset_consignment THEN false ELSE jualan_disahkan END,
    jumlah = v_jumlah_baru,
    jumlah_asal = v_sub_baru
  WHERE id = p_transaksi_id;

  IF v_trx.status = 'hutang' AND v_trx.kedai_id IS NOT NULL THEN
    UPDATE kedai SET hutang = GREATEST(0, hutang - v_jumlah_lama + v_jumlah_baru) WHERE id = v_trx.kedai_id;
  END IF;

  RETURN jsonb_build_object('qty_lama', v_qty_lama, 'qty_baru', v_qty_baru, 'jumlah_lama', v_jumlah_lama, 'jumlah_baru', v_jumlah_baru, 'pengesahan_direset', v_reset_consignment);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.tukar_produk_transaksi(text, text, text, int, uuid) TO authenticated;

-- Betulkan T5091574 sedia ada yg terjejas.
UPDATE transaksi SET jualan_disahkan = false, items_terjual = NULL, items_pulang = NULL
WHERE id = 'T5091574' AND NOT (items_terjual IS NULL AND items_pulang IS NULL AND jualan_disahkan = false);
