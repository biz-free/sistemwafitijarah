-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 82: Pemilik boleh backdate tarikh transaksi di Rekod
-- Baru (Tab Hantar) — utk rekod susulan transaksi yang terlepas dicatat
-- live. Resit ikut tarikh terpilih (guna transaksi.tarikh_masa terus,
-- tiada perubahan di renderResit()). Baucar harian sedia ada (draf/
-- diluluskan) utk pekerja+tarikh terbabit dibatalkan automatik supaya
-- pemilik nampak & jana/luluskan semula dengan angka upah yang betul
-- (bukan biar senyap dgn angka lama yang dah usang).
-- ═══════════════════════════════════════════════════════════

-- 1. Benarkan status 'dibatalkan' pada baucar_bayaran
ALTER TABLE public.baucar_bayaran DROP CONSTRAINT IF EXISTS baucar_bayaran_status_check;
ALTER TABLE public.baucar_bayaran ADD CONSTRAINT baucar_bayaran_status_check
  CHECK (status = ANY (ARRAY['draf','diluluskan','dibayar','dibatalkan']));

-- 2. submit_penghantaran — tambah p_tarikh_masa (pemilik sahaja boleh guna, sama
--    corak dengan p_pekerja_id_override), + auto-batal baucar harian usang.
DROP FUNCTION IF EXISTS public.submit_penghantaran(text, text, jsonb, double precision, text, text, text, double precision, text, text, double precision, double precision, text, uuid);

CREATE OR REPLACE FUNCTION public.submit_penghantaran(p_id text, p_kedai_id text, p_items jsonb, p_jumlah double precision, p_status text, p_nota text, p_resit text, p_jarak_km double precision DEFAULT 0, p_nama_pembeli text DEFAULT NULL::text, p_kaedah_bayaran text DEFAULT 'tunai'::text, p_jumlah_asal double precision DEFAULT NULL::double precision, p_diskaun_peratus double precision DEFAULT 0, p_resit_bukti_url text DEFAULT NULL::text, p_pekerja_id_override uuid DEFAULT NULL::uuid, p_tarikh_masa timestamptz DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE item jsonb; v_pekerja_id uuid; v_tarikh_masa timestamptz;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid()) THEN
    RAISE EXCEPTION 'Tidak dibenarkan';
  END IF;

  v_pekerja_id := CASE WHEN p_pekerja_id_override IS NOT NULL AND is_pemilik() THEN p_pekerja_id_override ELSE auth.uid() END;
  v_tarikh_masa := CASE WHEN p_tarikh_masa IS NOT NULL AND is_pemilik() THEN p_tarikh_masa ELSE now() END;

  FOR item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    UPDATE stok_pekerja SET kuantiti = kuantiti - (item->>'qty')::int
      WHERE pekerja_id = v_pekerja_id AND stok_id = item->>'stokId' AND kuantiti >= (item->>'qty')::int;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Stok bawaan tidak mencukupi untuk %', item->>'stokId';
    END IF;
  END LOOP;

  INSERT INTO transaksi (id, kedai_id, nama_pembeli, items, jumlah, status, nota, resit, jarak_km, created_by, kaedah_bayaran, jumlah_asal, diskaun_peratus, jualan_disahkan, resit_bukti_url, tarikh_masa)
  VALUES (p_id, p_kedai_id, p_nama_pembeli, p_items, p_jumlah, p_status, p_nota, p_resit, p_jarak_km, v_pekerja_id::text, p_kaedah_bayaran, COALESCE(p_jumlah_asal, p_jumlah), p_diskaun_peratus, (p_kaedah_bayaran <> 'consignment'), p_resit_bukti_url, v_tarikh_masa);

  UPDATE kedai SET
    hutang = hutang + (CASE WHEN p_status = 'hutang' THEN p_jumlah ELSE 0 END),
    last_visit = CURRENT_DATE::text
  WHERE id = p_kedai_id;

  -- Transaksi baharu ubah jumlah upah sepatutnya utk hari tu — baucar harian yang
  -- mungkin dah dijana (draf/diluluskan) utk pekerja+tarikh ni jadi USANG.
  UPDATE baucar_bayaran SET status = 'dibatalkan'
    WHERE pekerja_id = v_pekerja_id AND kategori = 'upah_harian'
      AND tarikh = (v_tarikh_masa AT TIME ZONE 'Asia/Kuala_Lumpur')::date
      AND status IN ('draf','diluluskan');
END;
$function$;
