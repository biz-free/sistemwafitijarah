-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 128: Baiki sahkan_jualan_konsainan() — kreditkan balik
-- stok_pekerja bila barang consignment DIPULANGKAN (tak laku).
--
-- PUNCA (siasatan aduan Nadia "stok tak tally", cth Tamar Cocoa Papan):
-- submit_penghantaran() TOLAK stok_pekerja SEPENUHNYA (ikut p_items) pada
-- saat transaksi consignment dicipta — termasuk barang yang akhirnya TAK
-- LAKU. Bila barang tu kemudian disahkan "pulang" (qtyPulang) melalui
-- sahkan_jualan_konsainan(), fungsi tu cuma kemaskini rekod transaksi
-- (items_pulang/jumlah/hutang kedai) — TIDAK PERNAH kreditkan balik
-- kuantiti ke stok_pekerja walaupun barang tu secara fizikal kembali ke
-- beg pekerja. Barang jadi "hilang" kekal drpd sistem (bukan di beg
-- pekerja, bukan di gudang, bukan direkod terjual/lupus).
--
-- Nasib baik ciri "pulang consignment" belum pernah digunakan sebenar
-- (0 rekod items_pulang wujud setakat siasatan ini) — jadi bukan punca
-- percanggahan SEDIA ADA, tapi PASTI akan sebabkan masalah sama berulang
-- pada masa depan bila ciri ni mula digunakan. Dibetulkan sebelum sempat
-- berlaku.
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.sahkan_jualan_konsainan(p_transaksi_id text, p_items jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
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
  v_pekerja_id uuid;
BEGIN
  SELECT * INTO v_trx FROM transaksi WHERE id = p_transaksi_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Transaksi tidak dijumpai'; END IF;
  IF NOT (is_pemilik() OR v_trx.created_by = auth.uid()::text) THEN
    RAISE EXCEPTION 'Tidak dibenarkan sahkan jualan transaksi ini';
  END IF;
  IF v_trx.kaedah_bayaran <> 'consignment' THEN RAISE EXCEPTION 'Transaksi ini bukan consignment'; END IF;
  IF v_trx.jualan_disahkan THEN RAISE EXCEPTION 'Jualan sudah disahkan PENUH sebelum ini — tiada baki tertinggal'; END IF;

  BEGIN
    v_pekerja_id := v_trx.created_by::uuid;
  EXCEPTION WHEN others THEN
    v_pekerja_id := NULL;
  END;

  SELECT jsonb_object_agg(i->>'stokId', (i->>'qty')::int) INTO v_map_dihantar FROM jsonb_array_elements(v_trx.items) i;
  SELECT jsonb_object_agg(i->>'stokId', COALESCE((i->>'harga')::double precision, 0)) INTO v_map_harga FROM jsonb_array_elements(v_trx.items) i;
  SELECT COALESCE(jsonb_object_agg(i->>'stokId', (i->>'qty')::int), '{}'::jsonb) INTO v_map_terjual FROM jsonb_array_elements(COALESCE(v_trx.items_terjual, '[]'::jsonb)) i;
  SELECT COALESCE(jsonb_object_agg(i->>'stokId', (i->>'qty')::int), '{}'::jsonb) INTO v_map_pulang FROM jsonb_array_elements(COALESCE(v_trx.items_pulang, '[]'::jsonb)) i;

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

      -- BAHARU: kreditkan balik ke stok_pekerja — barang tak laku secara fizikal
      -- kembali ke beg pekerja yg hantar transaksi ni, bukan terus hilang.
      IF v_pekerja_id IS NOT NULL THEN
        INSERT INTO stok_pekerja (pekerja_id, stok_id, kuantiti) VALUES (v_pekerja_id, v_stok_id, v_qty_p)
          ON CONFLICT (pekerja_id, stok_id) DO UPDATE SET kuantiti = stok_pekerja.kuantiti + v_qty_p;
      END IF;
    END IF;

    v_map_terjual := jsonb_set(v_map_terjual, ARRAY[v_stok_id], to_jsonb(COALESCE((v_map_terjual->>v_stok_id)::int, 0) + v_qty_t), true);
    v_map_pulang := jsonb_set(v_map_pulang, ARRAY[v_stok_id], to_jsonb(COALESCE((v_map_pulang->>v_stok_id)::int, 0) + v_qty_p), true);
  END LOOP;

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

  IF v_trx.status = 'hutang' AND v_trx.kedai_id IS NOT NULL AND v_pulang_value_baru <> 0 THEN
    UPDATE kedai SET hutang = GREATEST(0, hutang - (v_pulang_value_baru * (1 - COALESCE(v_trx.diskaun_peratus, 0) / 100))) WHERE id = v_trx.kedai_id;
  END IF;
END;
$function$;
