-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 77: (1) Pemilik boleh rekod Hantar/Rosak-Expired
-- bagi pihak pekerja lain, (2) resit utk Rosak/Expired.
--
-- Setiap RPC di-DROP dahulu (bukan CREATE OR REPLACE terus) sebab
-- tambah parameter baharu = signature berbeza — kalau tak drop,
-- overload lama akan wujud serentak & buat panggilan client sedia
-- ada (bilangan argumen asal) jadi ambiguous.
--
-- p_pekerja_id_override: kalau diisi DAN pemanggil is_pemilik(),
-- rekod (stok bawaan ditolak drpd, created_by/pekerja_id disimpan
-- sebagai) pekerja BERKENAAN, bukan pemilik sendiri. Pekerja biasa
-- yang cuba isi override ni diabaikan senyap (guna auth.uid() juga).
--
-- p_resit: nombor resit sama (genResit() client) dikongsi merentasi
-- SEMUA baris pelupusan_stok dari SATU hantaran borang (cth: 3 item
-- dilupuskan = 3 baris, semua kongsi 1 no. resit) — membolehkan 1
-- resit gabungan dijana utk keseluruhan hantaran, bukan per-baris.
-- ═══════════════════════════════════════════════════════════

ALTER TABLE public.pelupusan_stok ADD COLUMN IF NOT EXISTS resit text;

-- ── submit_penghantaran (Kedai Destinasi / Belian Peribadi) ──
DROP FUNCTION IF EXISTS public.submit_penghantaran(text, text, jsonb, double precision, text, text, text, double precision, text, text, double precision, double precision, text);

CREATE OR REPLACE FUNCTION public.submit_penghantaran(
  p_id text, p_kedai_id text, p_items jsonb, p_jumlah double precision, p_status text, p_nota text, p_resit text,
  p_jarak_km double precision DEFAULT 0, p_nama_pembeli text DEFAULT NULL,
  p_kaedah_bayaran text DEFAULT 'tunai', p_jumlah_asal double precision DEFAULT NULL, p_diskaun_peratus double precision DEFAULT 0,
  p_resit_bukti_url text DEFAULT NULL, p_pekerja_id_override uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE item jsonb; v_pekerja_id uuid;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid()) THEN
    RAISE EXCEPTION 'Tidak dibenarkan';
  END IF;

  v_pekerja_id := CASE WHEN p_pekerja_id_override IS NOT NULL AND is_pemilik() THEN p_pekerja_id_override ELSE auth.uid() END;

  FOR item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    UPDATE stok_pekerja SET kuantiti = kuantiti - (item->>'qty')::int
      WHERE pekerja_id = v_pekerja_id AND stok_id = item->>'stokId' AND kuantiti >= (item->>'qty')::int;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Stok bawaan tidak mencukupi untuk %', item->>'stokId';
    END IF;
  END LOOP;

  INSERT INTO transaksi (id, kedai_id, nama_pembeli, items, jumlah, status, nota, resit, jarak_km, created_by, kaedah_bayaran, jumlah_asal, diskaun_peratus, jualan_disahkan, resit_bukti_url)
  VALUES (p_id, p_kedai_id, p_nama_pembeli, p_items, p_jumlah, p_status, p_nota, p_resit, p_jarak_km, v_pekerja_id::text, p_kaedah_bayaran, COALESCE(p_jumlah_asal, p_jumlah), p_diskaun_peratus, (p_kaedah_bayaran <> 'consignment'), p_resit_bukti_url);

  UPDATE kedai SET
    hutang = hutang + (CASE WHEN p_status = 'hutang' THEN p_jumlah ELSE 0 END),
    last_visit = CURRENT_DATE::text
  WHERE id = p_kedai_id;
END;
$function$;
GRANT EXECUTE ON FUNCTION public.submit_penghantaran(text, text, jsonb, double precision, text, text, text, double precision, text, text, double precision, double precision, text, uuid) TO authenticated;

-- ── lupus_stok_pekerja (Rosak/Expired biasa, tiada tukar) ──
DROP FUNCTION IF EXISTS public.lupus_stok_pekerja(jsonb, text, text);

CREATE OR REPLACE FUNCTION public.lupus_stok_pekerja(p_items jsonb, p_sebab text, p_nota text DEFAULT NULL, p_resit text DEFAULT NULL, p_pekerja_id_override uuid DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE item jsonb; v_harga_beli float; v_qty int; v_pekerja_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Log masuk diperlukan'; END IF;
  v_pekerja_id := CASE WHEN p_pekerja_id_override IS NOT NULL AND is_pemilik() THEN p_pekerja_id_override ELSE auth.uid() END;

  FOR item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_qty := (item->>'qty')::int;
    IF v_qty <= 0 THEN RAISE EXCEPTION 'Kuantiti mesti lebih 0'; END IF;
    UPDATE stok_pekerja SET kuantiti = kuantiti - v_qty
      WHERE pekerja_id = v_pekerja_id AND stok_id = item->>'stokId' AND kuantiti >= v_qty;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Stok bawaan tidak mencukupi untuk %', item->>'stokId';
    END IF;
    SELECT harga_beli INTO v_harga_beli FROM stok WHERE id = item->>'stokId';
    INSERT INTO pelupusan_stok (id, pekerja_id, stok_id, kuantiti, sebab, nota, kos, resit)
      VALUES (gen_random_uuid()::text, v_pekerja_id, item->>'stokId', v_qty, p_sebab, p_nota, COALESCE(v_harga_beli,0)*v_qty, p_resit);
  END LOOP;
END;
$function$;
GRANT EXECUTE ON FUNCTION public.lupus_stok_pekerja(jsonb, text, text, text, uuid) TO authenticated;

-- ── tukar_stok_expired_kedai (Rosak/Expired + tukar barang dgn kedai) ──
DROP FUNCTION IF EXISTS public.tukar_stok_expired_kedai(text, jsonb, jsonb, text, text);

CREATE OR REPLACE FUNCTION public.tukar_stok_expired_kedai(p_kedai_id text, p_items_expired jsonb, p_items_gantian jsonb, p_sebab_expired text DEFAULT 'expired', p_nota text DEFAULT NULL, p_resit text DEFAULT NULL, p_pekerja_id_override uuid DEFAULT NULL)
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

  UPDATE kedai SET last_visit = CURRENT_DATE::text WHERE id = p_kedai_id;
END;
$function$;
GRANT EXECUTE ON FUNCTION public.tukar_stok_expired_kedai(text, jsonb, jsonb, text, text, text, uuid) TO authenticated;
