-- SQL_TAMBAHAN_140: Tukar Produk Transaksi — pemilik boleh pilih PEKERJA sumber stok
-- gantian & KUANTITI baharu (susulan #115) — sebelum ni kuantiti dikunci ikut rekod
-- asal & stok gantian WAJIB drpd pekerja yg sama (created_by transaksi), tak fleksibel
-- utk kes cth produk betul cuma ada dlm bawaan pekerja LAIN.
--
-- created_by transaksi KEKAL tak berubah (upah/laporan tetap milik pekerja yg
-- rekod/hantar asal) — cuma SUMBER stok gantian (stok_pekerja mana yg ditolak)
-- boleh dipilih berlainan drpd pekerja asal jika perlu. Produk LAMA sentiasa
-- dipulangkan ke pekerja ASAL (created_by), tak kira pekerja sasaran dipilih siapa.
--
-- Pengesahan tambahan: kuantiti baharu TAK BOLEH kurang drpd jumlah yg dah disahkan
-- terjual+pulang (consignment) utk produk lama tu — elak kuantiti "hilang" drpd
-- rekod yg dah disahkan sebahagian.
--
-- Diuji live (BEGIN/ROLLBACK) — T5091574 (S003 qty1 → S001 qty2, pekerja sasaran
-- ditukar ke Nadia): stok bawaan Aremier (S003) +1 betul, stok bawaan Nadia (S001)
-- -2 betul, created_by transaksi kekal Aremier, items/jumlah dikira semula ikut
-- qty & harga baharu. Ujian pengesahan qty<=0 turut disahkan ditolak.
DROP FUNCTION IF EXISTS public.tukar_produk_transaksi(text, text, text);

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
  v_items_baru jsonb; v_items_terjual_baru jsonb; v_items_pulang_baru jsonb;
  v_terjual_pulang_sedia int := 0;
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

  SELECT COALESCE((SELECT (it->>'qty')::int FROM jsonb_array_elements(COALESCE(v_trx.items_terjual,'[]'::jsonb)) it WHERE it->>'stokId'=p_stok_id_lama),0)
       + COALESCE((SELECT (it->>'qty')::int FROM jsonb_array_elements(COALESCE(v_trx.items_pulang,'[]'::jsonb)) it WHERE it->>'stokId'=p_stok_id_lama),0)
    INTO v_terjual_pulang_sedia;
  IF v_qty_baru < v_terjual_pulang_sedia THEN
    RAISE EXCEPTION 'Kuantiti baharu (%) tak boleh kurang drpd jumlah dah disahkan terjual+pulang (%)', v_qty_baru, v_terjual_pulang_sedia;
  END IF;

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

  RETURN jsonb_build_object('qty_lama', v_qty_lama, 'qty_baru', v_qty_baru, 'jumlah_lama', v_jumlah_lama, 'jumlah_baru', v_jumlah_baru);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.tukar_produk_transaksi(text, text, text, int, uuid) TO authenticated;
