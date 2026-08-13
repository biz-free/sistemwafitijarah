-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 102: Kedai keluar Route automatik sebaik dilawati.
-- Pemilik minta: route sepatutnya jadi senarai "PERLU dilawat", bukan
-- senarai kekal — elak kekeliruan pekerja (kedai yg dah dihantar tapi
-- masih tersenarai dlm route buat pekerja fikir kena pergi lagi).
--
-- Disahkan bersama pemilik: (1) route_id dikosongkan KEKAL (bukan cuma
-- hilang drpd Tugasan Hari Ini) — pemilik kena tambah balik manual utk
-- pusingan lawatan akan datang; (2) "sudah dilawati" = last_visit wujud
-- BILA-BILA masa (bukan terhad hari ini sahaja).
--
-- Dikemaskini pada 2 RPC yg set last_visit (mana-mana kedai fizikal
-- disentuh pekerja): submit_penghantaran (hantar biasa) & tukar_stok_
-- expired_kedai (tukar barang expired). lupus_stok_pekerja tak sentuh
-- kedai langsung, jadi tak relevan.
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.submit_penghantaran(
  p_id text, p_kedai_id text, p_items jsonb, p_jumlah double precision, p_status text, p_nota text, p_resit text,
  p_jarak_km double precision DEFAULT 0, p_nama_pembeli text DEFAULT NULL::text, p_kaedah_bayaran text DEFAULT 'tunai'::text,
  p_jumlah_asal double precision DEFAULT NULL::double precision, p_diskaun_peratus double precision DEFAULT 0,
  p_resit_bukti_url text DEFAULT NULL::text, p_pekerja_id_override uuid DEFAULT NULL::uuid,
  p_tarikh_masa timestamp with time zone DEFAULT NULL::timestamp with time zone,
  p_tarikh_akhir_bayaran date DEFAULT NULL::date
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE item jsonb; v_pekerja_id uuid; v_tarikh_masa timestamptz;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid()) THEN
    RAISE EXCEPTION 'Tidak dibenarkan';
  END IF;

  v_pekerja_id := CASE WHEN p_pekerja_id_override IS NOT NULL AND is_pemilik() THEN p_pekerja_id_override ELSE auth.uid() END;
  v_tarikh_masa := CASE WHEN p_tarikh_masa IS NOT NULL AND is_pemilik() THEN p_tarikh_masa ELSE now() END;

  IF EXISTS (
    SELECT 1 FROM transaksi
    WHERE created_by = v_pekerja_id::text
      AND kedai_id IS NOT DISTINCT FROM p_kedai_id
      AND items = p_items
      AND jumlah = p_jumlah
      AND kaedah_bayaran = p_kaedah_bayaran
      AND tarikh_masa BETWEEN v_tarikh_masa - interval '5 minutes' AND v_tarikh_masa + interval '5 minutes'
  ) THEN
    RAISE EXCEPTION 'Transaksi sama persis (kedai, barang & jumlah sama) baru sahaja direkod dalam 5 minit lepas — kemungkinan tersilap tekan dua kali. Semak Sejarah Penghantaran sebelum cuba lagi.';
  END IF;

  FOR item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    UPDATE stok_pekerja SET kuantiti = kuantiti - (item->>'qty')::int
      WHERE pekerja_id = v_pekerja_id AND stok_id = item->>'stokId' AND kuantiti >= (item->>'qty')::int;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Stok bawaan tidak mencukupi untuk %', item->>'stokId';
    END IF;
  END LOOP;

  INSERT INTO transaksi (id, kedai_id, nama_pembeli, items, jumlah, status, nota, resit, jarak_km, created_by, kaedah_bayaran, jumlah_asal, diskaun_peratus, jualan_disahkan, resit_bukti_url, tarikh_masa, tarikh_akhir_bayaran)
  VALUES (p_id, p_kedai_id, p_nama_pembeli, p_items, p_jumlah, p_status, p_nota, p_resit, p_jarak_km, v_pekerja_id::text, p_kaedah_bayaran, COALESCE(p_jumlah_asal, p_jumlah), p_diskaun_peratus, (p_kaedah_bayaran <> 'consignment'), p_resit_bukti_url, v_tarikh_masa, p_tarikh_akhir_bayaran);

  -- Kedai keluar route automatik sebaik dilawati — route = senarai "PERLU dilawat",
  -- bukan senarai kekal. Pemilik kena tambah balik manual utk pusingan akan datang.
  UPDATE kedai SET
    hutang = hutang + (CASE WHEN p_status = 'hutang' THEN p_jumlah ELSE 0 END),
    last_visit = CURRENT_DATE::text,
    route_id = NULL,
    route_urutan = NULL
  WHERE id = p_kedai_id;

  UPDATE baucar_bayaran SET status = 'dibatalkan'
    WHERE pekerja_id = v_pekerja_id AND kategori = 'upah_harian'
      AND tarikh = (v_tarikh_masa AT TIME ZONE 'Asia/Kuala_Lumpur')::date
      AND status IN ('draf','diluluskan');

  IF p_kedai_id IS NOT NULL THEN
    PERFORM sync_bonus_kedai_baru(p_kedai_id);
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.tukar_stok_expired_kedai(p_kedai_id text, p_items_expired jsonb, p_items_gantian jsonb, p_sebab_expired text DEFAULT 'expired'::text, p_nota text DEFAULT NULL::text, p_resit text DEFAULT NULL::text, p_pekerja_id_override uuid DEFAULT NULL::uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE item jsonb; v_harga_beli float; v_qty int; v_pekerja_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Log masuk diperlukan'; END IF;
  IF NOT EXISTS (SELECT 1 FROM kedai WHERE id = p_kedai_id) THEN
    RAISE EXCEPTION 'Kedai tidak dijumpai';
  END IF;

  v_pekerja_id := CASE WHEN p_pekerja_id_override IS NOT NULL AND is_pemilik() THEN p_pekerja_id_override ELSE auth.uid() END;

  FOR item IN SELECT * FROM jsonb_array_elements(COALESCE(p_items_expired, '[]'::jsonb)) LOOP
    v_qty := (item->>'qty')::int;
    IF v_qty <= 0 THEN RAISE EXCEPTION 'Kuantiti mesti lebih 0'; END IF;
    SELECT harga_beli INTO v_harga_beli FROM stok WHERE id = item->>'stokId';
    IF v_harga_beli IS NULL THEN RAISE EXCEPTION 'Produk % tidak wujud atau telah dipadam', item->>'stokId'; END IF;

    INSERT INTO stok_pekerja (pekerja_id, stok_id, kuantiti) VALUES (v_pekerja_id, item->>'stokId', v_qty)
      ON CONFLICT (pekerja_id, stok_id) DO UPDATE SET kuantiti = stok_pekerja.kuantiti + v_qty;
    UPDATE stok_pekerja SET kuantiti = kuantiti - v_qty
      WHERE pekerja_id = v_pekerja_id AND stok_id = item->>'stokId';

    INSERT INTO pelupusan_stok (id, pekerja_id, kedai_id, stok_id, kuantiti, sebab, jenis, nota, kos, resit)
      VALUES (gen_random_uuid()::text, v_pekerja_id, p_kedai_id, item->>'stokId', v_qty, p_sebab_expired, 'tukar_ambil', p_nota, v_harga_beli * v_qty, p_resit);
  END LOOP;

  FOR item IN SELECT * FROM jsonb_array_elements(COALESCE(p_items_gantian, '[]'::jsonb)) LOOP
    v_qty := (item->>'qty')::int;
    IF v_qty <= 0 THEN RAISE EXCEPTION 'Kuantiti mesti lebih 0'; END IF;
    UPDATE stok_pekerja SET kuantiti = kuantiti - v_qty
      WHERE pekerja_id = v_pekerja_id AND stok_id = item->>'stokId' AND kuantiti >= v_qty;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Stok bawaan tidak mencukupi untuk %', item->>'stokId';
    END IF;
    SELECT harga_beli INTO v_harga_beli FROM stok WHERE id = item->>'stokId';
    INSERT INTO pelupusan_stok (id, pekerja_id, kedai_id, stok_id, kuantiti, sebab, jenis, nota, kos, resit)
      VALUES (gen_random_uuid()::text, v_pekerja_id, p_kedai_id, item->>'stokId', v_qty, 'gantian_tukar', 'tukar_beri', p_nota, COALESCE(v_harga_beli, 0) * v_qty, p_resit);
  END LOOP;

  UPDATE kedai SET last_visit = CURRENT_DATE::text, route_id = NULL, route_urutan = NULL WHERE id = p_kedai_id;
END;
$function$;
