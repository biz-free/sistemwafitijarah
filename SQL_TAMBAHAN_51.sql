-- SQL_TAMBAHAN_51: Tukar Barang Expired Dengan Barang Lain (dalam tab Rosak/Expired)
--
-- MASALAH: Bila kedai nak tukar barang expired dengan barang lain, staff
-- terpaksa rekod sebagai penghantaran "Kedai Destinasi" biasa — yang mana
-- jumlah barang gantian selalu ≥ RM500 dan secara automatik dapat diskaun
-- transfer/COD (kiraDiskaunHantarPeratus). Ini menambah kerugian sebab kedai
-- dapat diskaun ATAS barang yang sepatutnya percuma (gantian expired), bukan
-- jualan sebenar.
--
-- PENYELESAIAN: Tambah mod "Tukar" dalam tab Rosak/Expired — rekod DUA
-- belah pertukaran sekali gus, kedua-duanya sebagai KERUGIAN (bukan
-- jualan), TIADA kaedah bayaran/diskaun automatik langsung:
--   1. Barang expired diambil balik dari kedai (kos kerugian, TIADA potong
--      stok bawaan pekerja — barang ni bukan dari stok bawaan pekerja pun).
--   2. Barang gantian diberi PERCUMA kepada kedai (potong stok bawaan
--      pekerja sebenar, kos turut direkod sebagai kerugian).
--
-- Kedua-dua belah direkod dalam pelupusan_stok (jadual sedia ada) dengan
-- kedai_id + jenis baharu supaya boleh dikesan/audit ikut kedai.

ALTER TABLE pelupusan_stok ADD COLUMN IF NOT EXISTS kedai_id text REFERENCES kedai(id) ON DELETE SET NULL;
ALTER TABLE pelupusan_stok ADD COLUMN IF NOT EXISTS jenis text DEFAULT 'lupus';

CREATE OR REPLACE FUNCTION public.tukar_stok_expired_kedai(
  p_kedai_id text, p_items_expired jsonb, p_items_gantian jsonb,
  p_sebab_expired text DEFAULT 'expired'::text, p_nota text DEFAULT NULL::text
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE item jsonb; v_harga_beli float; v_qty int;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM kedai WHERE id = p_kedai_id) THEN
    RAISE EXCEPTION 'Kedai tidak dijumpai';
  END IF;

  -- Belah 1: barang expired diambil balik dari kedai — kerugian sahaja, TIADA potong stok bawaan pekerja.
  FOR item IN SELECT * FROM jsonb_array_elements(COALESCE(p_items_expired, '[]'::jsonb)) LOOP
    v_qty := (item->>'qty')::int;
    IF v_qty <= 0 THEN RAISE EXCEPTION 'Kuantiti mesti lebih 0'; END IF;
    SELECT harga_beli INTO v_harga_beli FROM stok WHERE id = item->>'stokId';
    IF v_harga_beli IS NULL THEN RAISE EXCEPTION 'Produk % tidak wujud atau telah dipadam', item->>'stokId'; END IF;
    INSERT INTO pelupusan_stok (id, pekerja_id, kedai_id, stok_id, kuantiti, sebab, jenis, nota, kos)
      VALUES (gen_random_uuid()::text, auth.uid(), p_kedai_id, item->>'stokId', v_qty, p_sebab_expired, 'tukar_ambil', p_nota, v_harga_beli * v_qty);
  END LOOP;

  -- Belah 2: barang gantian diberi PERCUMA kepada kedai — potong stok bawaan pekerja sebenar, turut kerugian.
  FOR item IN SELECT * FROM jsonb_array_elements(COALESCE(p_items_gantian, '[]'::jsonb)) LOOP
    v_qty := (item->>'qty')::int;
    IF v_qty <= 0 THEN RAISE EXCEPTION 'Kuantiti mesti lebih 0'; END IF;
    UPDATE stok_pekerja SET kuantiti = kuantiti - v_qty
      WHERE pekerja_id = auth.uid() AND stok_id = item->>'stokId' AND kuantiti >= v_qty;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Stok bawaan anda tidak mencukupi untuk %', item->>'stokId';
    END IF;
    SELECT harga_beli INTO v_harga_beli FROM stok WHERE id = item->>'stokId';
    INSERT INTO pelupusan_stok (id, pekerja_id, kedai_id, stok_id, kuantiti, sebab, jenis, nota, kos)
      VALUES (gen_random_uuid()::text, auth.uid(), p_kedai_id, item->>'stokId', v_qty, 'gantian_tukar', 'tukar_beri', p_nota, COALESCE(v_harga_beli, 0) * v_qty);
  END LOOP;

  UPDATE kedai SET last_visit = CURRENT_DATE::text WHERE id = p_kedai_id;
END;
$function$;
