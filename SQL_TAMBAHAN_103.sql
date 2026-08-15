-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 103: Pertahanan lapisan kedua (server-side) untuk
-- pilihan diskaun WAJIB di Tab Hantar > Rekod Baru. Semakan sedia
-- ada (pengurusan.html: setDiskaunPilihan/submitHantarSebenar) cuma
-- di peringkat client JS — boleh dipintas jika seseorang panggil
-- RPC terus. Tambah p_diskaun_pilihan pada submit_penghantaran
-- (parameter baharu dgn DEFAULT — CREATE OR REPLACE selamat, tak
-- cipta overload baharu) & tolak submission jika:
--   (a) jumlah_asal >= minima_transfer tapi p_diskaun_pilihan
--       tiada/tidak sah ('0'/'cod'/'transfer'), ATAU
--   (b) p_diskaun_peratus dihantar tak sepadan dgn kadar rasmi utk
--       pilihan tsb (elak tampering terus pada peratus).
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.submit_penghantaran(
  p_id text, p_kedai_id text, p_items jsonb, p_jumlah double precision, p_status text, p_nota text, p_resit text,
  p_jarak_km double precision DEFAULT 0, p_nama_pembeli text DEFAULT NULL::text, p_kaedah_bayaran text DEFAULT 'tunai'::text,
  p_jumlah_asal double precision DEFAULT NULL::double precision, p_diskaun_peratus double precision DEFAULT 0,
  p_resit_bukti_url text DEFAULT NULL::text, p_pekerja_id_override uuid DEFAULT NULL::uuid,
  p_tarikh_masa timestamp with time zone DEFAULT NULL::timestamp with time zone,
  p_tarikh_akhir_bayaran date DEFAULT NULL::date,
  p_diskaun_pilihan text DEFAULT NULL::text
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
  item jsonb; v_pekerja_id uuid; v_tarikh_masa timestamptz;
  v_minima double precision; v_kadar_cod double precision; v_kadar_transfer double precision;
  v_jumlah_asal_efektif double precision;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid()) THEN
    RAISE EXCEPTION 'Tidak dibenarkan';
  END IF;

  v_pekerja_id := CASE WHEN p_pekerja_id_override IS NOT NULL AND is_pemilik() THEN p_pekerja_id_override ELSE auth.uid() END;
  v_tarikh_masa := CASE WHEN p_tarikh_masa IS NOT NULL AND is_pemilik() THEN p_tarikh_masa ELSE now() END;

  -- Pilihan diskaun WAJIB bila jumlah cukup minima — sama dgn syarat client
  -- (pengurusan.html calcTotal()/submitHantarSebenar()), sekat di sini juga
  -- supaya panggilan RPC terus tak boleh pintas semakan tersebut.
  SELECT minima_transfer, diskaun_cod_peratus, diskaun_peratus
    INTO v_minima, v_kadar_cod, v_kadar_transfer
    FROM tetapan WHERE id = 1;

  v_jumlah_asal_efektif := COALESCE(p_jumlah_asal, p_jumlah);

  IF COALESCE(v_minima, 0) > 0 AND v_jumlah_asal_efektif >= v_minima THEN
    IF p_diskaun_pilihan IS NULL OR p_diskaun_pilihan NOT IN ('0', 'cod', 'transfer') THEN
      RAISE EXCEPTION 'Pilihan diskaun wajib (0%% / kadar tunai / kadar transfer) untuk jumlah >= %', v_minima;
    END IF;
    IF (p_diskaun_pilihan = '0' AND p_diskaun_peratus IS DISTINCT FROM 0)
       OR (p_diskaun_pilihan = 'cod' AND p_diskaun_peratus IS DISTINCT FROM COALESCE(v_kadar_cod, 0))
       OR (p_diskaun_pilihan = 'transfer' AND p_diskaun_peratus IS DISTINCT FROM COALESCE(v_kadar_transfer, 0)) THEN
      RAISE EXCEPTION 'Peratus diskaun tidak sepadan dengan pilihan yang dihantar';
    END IF;
  END IF;

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
