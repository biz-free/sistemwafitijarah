-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 98: Tarikh Akhir Bayaran (due date) untuk transaksi
-- kaedah bayaran Hutang — pekerja pilih di Tab Hantar semasa rekod
-- penghantaran dgn kaedah "Hutang". Bila tarikh ni sampai/lepas &
-- transaksi masih status='hutang', kedai + pekerja berkaitan akan
-- dipaparkan sbg amaran di Dashboard (pekerja nampak sendiri sahaja,
-- pemilik nampak semua + nama pekerja).
--
-- NOTA (pengajaran drpd kesilapan SQL_TAMBAHAN_90/94): CREATE OR REPLACE
-- + parameter baharu di HUJUNG (walaupun berdefault) MASIH cipta overload
-- BAHARU dlm projek ni (bukan ganti) — kena DROP signature LAMA dahulu.
-- ═══════════════════════════════════════════════════════════

ALTER TABLE public.transaksi ADD COLUMN IF NOT EXISTS tarikh_akhir_bayaran date;

DROP FUNCTION IF EXISTS public.submit_penghantaran(text, text, jsonb, double precision, text, text, text, double precision, text, text, double precision, double precision, text, uuid, timestamptz);

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

  FOR item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    UPDATE stok_pekerja SET kuantiti = kuantiti - (item->>'qty')::int
      WHERE pekerja_id = v_pekerja_id AND stok_id = item->>'stokId' AND kuantiti >= (item->>'qty')::int;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Stok bawaan tidak mencukupi untuk %', item->>'stokId';
    END IF;
  END LOOP;

  INSERT INTO transaksi (id, kedai_id, nama_pembeli, items, jumlah, status, nota, resit, jarak_km, created_by, kaedah_bayaran, jumlah_asal, diskaun_peratus, jualan_disahkan, resit_bukti_url, tarikh_masa, tarikh_akhir_bayaran)
  VALUES (p_id, p_kedai_id, p_nama_pembeli, p_items, p_jumlah, p_status, p_nota, p_resit, p_jarak_km, v_pekerja_id::text, p_kaedah_bayaran, COALESCE(p_jumlah_asal, p_jumlah), p_diskaun_peratus, (p_kaedah_bayaran <> 'consignment'), p_resit_bukti_url, v_tarikh_masa, p_tarikh_akhir_bayaran);

  UPDATE kedai SET
    hutang = hutang + (CASE WHEN p_status = 'hutang' THEN p_jumlah ELSE 0 END),
    last_visit = CURRENT_DATE::text
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
