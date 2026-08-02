-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 80: Tukar Stok Expired (kedai) — barang expired yang
-- diambil BALIK dari kedai kini turut menyentuh Stok Bawaan Pekerja,
-- bukan terus jadi pelupusan tanpa jejak stok_pekerja langsung.
--
-- SEBELUM ini: barang expired diambil balik terus INSERT pelupusan_stok
-- sahaja — TIADA sentuhan stok_pekerja (anggapan asal: "barang ni dari
-- kedai, bukan bag pekerja"). Pemilik minta kekalkan jejak fizikal:
-- barang tu secara fizikal KINI di tangan pekerja (walau seketika)
-- sebelum dilupuskan, jadi patut TAMBAH stok bawaan dahulu, kemudian
-- TOLAK semula serta-merta dlm operasi sama sebagai pelupusan — hasil
-- bersih genap 0 (tiada perubahan angka akhir), tapi pergerakan penuh
-- "terima drpd kedai → lupus" kini direkod betul melalui stok_pekerja.
--
-- Barang GANTIAN (diberi kpd kedai) TIADA perubahan — ia MEMANG SUDAH
-- tolak stok_pekerja sejak awal (barang tu sememangnya dari bag pekerja).
-- ═══════════════════════════════════════════════════════════

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

    -- Tambah dulu (terima drpd kedai — kini di tangan pekerja), tolak semula serta-merta
    -- (dilupuskan). Guna INSERT..ON CONFLICT drpd tiada row stok_pekerja sedia ada lagi.
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

  UPDATE kedai SET last_visit = CURRENT_DATE::text WHERE id = p_kedai_id;
END;
$function$;
