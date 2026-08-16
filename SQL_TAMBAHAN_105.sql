-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 105: BETULKAN bug kritikal — Sahkan Jualan Consignment
-- salah anggap produk yang TAK disentuh pekerja sebagai "terjual
-- SEPENUHNYA", bukan "masih ada baki/belum pasti".
--
-- Punca: borang lama (jual-${t.id}-${i}) beri nilai LALAI = kuantiti
-- PENUH dihantar utk setiap produk. Bila pekerja cuma nak sahkan 1
-- drpd 2 produk (produk kedua masih ada baki di kedai, belum pasti
-- jual/tidak), input produk kedua yg TAK disentuh kekal pada nilai
-- lalai (penuh) — submit terus kira KEDUA-DUA produk terjual PENUH.
-- Disahkan pada rekod SEBENAR T9830103 (2 unit dihantar, pekerja
-- cuma jual 1, tapi items_terjual/jumlah rekod PENUH 2 unit).
--
-- Fix: redesign "Sahkan Jualan" jadi INKREMENTAL & 3-keadaan setiap
-- produk — Terjual / Pulang (tak laku, disahkan) / Baki (kekal
-- belum pasti, TAK dikira sama ada terjual atau pulang sehingga
-- pekerja kemaskini lagi pada lawatan akan datang). jualan_disahkan
-- (PENUH) hanya true bila SEMUA produk sudah baki=0.
--
-- items_pulang (BAHARU) jejak kumulatif kuantiti disahkan TAK laku/
-- dipulangkan berasingan drpd items_terjual (kumulatif kuantiti
-- disahkan terjual). jumlah/jumlah_asal transaksi & kedai.hutang
-- HANYA berkurang bila ada PULANG disahkan (barang terjual & baki
-- kedua-duanya kekal "berhutang" sehingga terbukti dipulangkan —
-- padan dgn model asal hutang-penuh-di-hadapan submit_penghantaran).
-- ═══════════════════════════════════════════════════════════

ALTER TABLE public.transaksi ADD COLUMN IF NOT EXISTS items_pulang jsonb;

CREATE OR REPLACE FUNCTION public.sahkan_jualan_konsainan(p_transaksi_id text, p_items jsonb)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
  v_trx RECORD;
  item jsonb;
  v_stok_id text;
  v_qty_t int;
  v_qty_p int;
  v_baki int;
  v_harga double precision;
  v_pulang_value_baru double precision := 0;
  v_semua_selesai boolean;
  v_map_dihantar jsonb;
  v_map_harga jsonb;
  v_map_terjual jsonb;
  v_map_pulang jsonb;
  v_arr_terjual jsonb;
  v_arr_pulang jsonb;
  v_jumlah_asal_terkini double precision;
  v_jumlah_terkini double precision;
BEGIN
  SELECT * INTO v_trx FROM transaksi WHERE id = p_transaksi_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Transaksi tidak dijumpai'; END IF;
  IF NOT (is_pemilik() OR v_trx.created_by = auth.uid()::text) THEN
    RAISE EXCEPTION 'Tidak dibenarkan sahkan jualan transaksi ini';
  END IF;
  IF v_trx.kaedah_bayaran <> 'consignment' THEN RAISE EXCEPTION 'Transaksi ini bukan consignment'; END IF;
  IF v_trx.jualan_disahkan THEN RAISE EXCEPTION 'Jualan sudah disahkan PENUH sebelum ini — tiada baki tertinggal'; END IF;

  SELECT jsonb_object_agg(i->>'stokId', (i->>'qty')::int) INTO v_map_dihantar FROM jsonb_array_elements(v_trx.items) i;
  SELECT jsonb_object_agg(i->>'stokId', COALESCE((i->>'harga')::double precision, 0)) INTO v_map_harga FROM jsonb_array_elements(v_trx.items) i;
  SELECT COALESCE(jsonb_object_agg(i->>'stokId', (i->>'qty')::int), '{}'::jsonb) INTO v_map_terjual FROM jsonb_array_elements(COALESCE(v_trx.items_terjual, '[]'::jsonb)) i;
  SELECT COALESCE(jsonb_object_agg(i->>'stokId', (i->>'qty')::int), '{}'::jsonb) INTO v_map_pulang FROM jsonb_array_elements(COALESCE(v_trx.items_pulang, '[]'::jsonb)) i;

  -- p_items = HANYA produk yang pekerja SECARA EKSPLISIT kemaskini pusingan ini
  -- (bentuk [{stokId, qtyTerjual, qtyPulang}]) — produk yang tak disenaraikan
  -- (atau 0/0) TAK disentuh langsung, baki dia kekal seperti sebelum ini.
  FOR item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_stok_id := item->>'stokId';
    v_qty_t := COALESCE((item->>'qtyTerjual')::int, 0);
    v_qty_p := COALESCE((item->>'qtyPulang')::int, 0);
    IF v_qty_t < 0 OR v_qty_p < 0 THEN RAISE EXCEPTION 'Kuantiti tidak sah untuk produk %', v_stok_id; END IF;
    IF NOT (v_map_dihantar ? v_stok_id) THEN RAISE EXCEPTION 'Produk % bukan sebahagian transaksi ini', v_stok_id; END IF;
    IF v_qty_t = 0 AND v_qty_p = 0 THEN CONTINUE; END IF;

    v_baki := (v_map_dihantar->>v_stok_id)::int - COALESCE((v_map_terjual->>v_stok_id)::int, 0) - COALESCE((v_map_pulang->>v_stok_id)::int, 0);
    IF (v_qty_t + v_qty_p) > v_baki THEN
      RAISE EXCEPTION 'Kuantiti terjual+pulang (%) melebihi baki semasa (%) untuk produk %', v_qty_t + v_qty_p, v_baki, v_stok_id;
    END IF;

    IF v_qty_p > 0 THEN
      v_harga := COALESCE((v_map_harga->>v_stok_id)::double precision, 0);
      v_pulang_value_baru := v_pulang_value_baru + (v_harga * v_qty_p);
    END IF;

    v_map_terjual := jsonb_set(v_map_terjual, ARRAY[v_stok_id], to_jsonb(COALESCE((v_map_terjual->>v_stok_id)::int, 0) + v_qty_t), true);
    v_map_pulang := jsonb_set(v_map_pulang, ARRAY[v_stok_id], to_jsonb(COALESCE((v_map_pulang->>v_stok_id)::int, 0) + v_qty_p), true);
  END LOOP;

  -- Selesai PENUH hanya bila SETIAP produk dihantar sudah habis diakaunkan
  -- (terjual + pulang = dihantar) — kalau ada satu baki pun, kekal separa.
  SELECT bool_and((v_map_dihantar->>key)::int <= (COALESCE((v_map_terjual->>key)::int, 0) + COALESCE((v_map_pulang->>key)::int, 0)))
    INTO v_semua_selesai
    FROM jsonb_object_keys(v_map_dihantar) key;

  SELECT COALESCE(jsonb_agg(jsonb_build_object('stokId', key, 'qty', value::int)) FILTER (WHERE value::int > 0), '[]'::jsonb)
    INTO v_arr_terjual FROM jsonb_each_text(v_map_terjual);
  SELECT COALESCE(jsonb_agg(jsonb_build_object('stokId', key, 'qty', value::int)) FILTER (WHERE value::int > 0), '[]'::jsonb)
    INTO v_arr_pulang FROM jsonb_each_text(v_map_pulang);

  v_jumlah_asal_terkini := v_trx.jumlah_asal - v_pulang_value_baru;
  v_jumlah_terkini := v_jumlah_asal_terkini * (1 - COALESCE(v_trx.diskaun_peratus, 0) / 100);

  UPDATE transaksi SET
    items_terjual = v_arr_terjual,
    items_pulang = v_arr_pulang,
    jualan_disahkan = v_semua_selesai,
    disahkan_oleh = auth.uid(),
    disahkan_pada = now(),
    jumlah = v_jumlah_terkini,
    jumlah_asal = v_jumlah_asal_terkini
  WHERE id = p_transaksi_id;

  -- Barang PULANG (tak laku, disahkan) sahaja yang gugurkan hutang — barang
  -- terjual & baki kedua-duanya kekal berhutang (padan model asal: hutang
  -- penuh direkod di hadapan semasa hantar, cuma pulang yg batalkannya).
  IF v_trx.status = 'hutang' AND v_trx.kedai_id IS NOT NULL AND v_pulang_value_baru <> 0 THEN
    UPDATE kedai SET hutang = GREATEST(0, hutang - (v_pulang_value_baru * (1 - COALESCE(v_trx.diskaun_peratus, 0) / 100))) WHERE id = v_trx.kedai_id;
  END IF;
END;
$function$;
