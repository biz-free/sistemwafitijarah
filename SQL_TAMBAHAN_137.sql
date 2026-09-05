-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 137: Baiki baris "Pelarasan Kos Dipulangkan" hilang bila baucar
-- harian dijana SEMULA (draf) untuk hari/pekerja yg SAMA (susulan #106/#107).
--
-- PUNCA: cipta_baucar_harian() cuma masukkan jsonb_build_object('pelarasan', ...)
-- ke `butiran` jika v_pelarasan (jumlah pelarasan status='belum_diselaraskan' YG
-- BARU dijumpai PADA PANGGILAN NI) > 0. Panggilan PERTAMA betul (upah ditolak +
-- butiran.pelarasan direkod, pelarasan ditanda 'sudah_diselaraskan'). Tapi kalau
-- fungsi dipanggil SEKALI LAGI utk hari/pekerja SAMA (draf, belum diluluskan) —
-- cth pekerja Thumb Out lagi/pemilik jana semula selepas kerja lengkap — panggilan
-- KEDUA ni jumpa pelarasan dah 'sudah_diselaraskan' (bkn 'belum_diselaraskan'
-- lagi), jadi v_pelarasan=0 pada panggilan ni → UPDATE timpa `butiran` guna
-- COALESCE(v_butiran, butiran) = p_butiran BAHARU (tiada kunci 'pelarasan')
-- WALAUPUN upah masih betul ditolak. Hasilnya: duit BETUL tapi baris audit
-- "🔻 Pelarasan Kos Dipulangkan" hilang drpd resit/baucar.
-- Ditemui pd PV-2026-0103 (Nadia, 3 Sep 2026) — pelarasan Agrobazaar Seri Indah
-- Bakery (RM37.97) terpakai betul tapi tak papar pada baucar akhir.
--
-- BAIKI: bila kemaskini baucar SEDIA ADA (draf), turut cari pelarasan yg SUDAH
-- pun terikat dgn baucar_id ni (status='sudah_diselaraskan' AND baucar_id=v_sedia_id)
-- drpd panggilan-panggilan SEBELUM ni, gabung dgn pelarasan BAHARU (jika ada) —
-- supaya butiran.pelarasan SENTIASA papar jumlah PENUH yg pernah ditolak drpd
-- baucar ni, tak kira berapa kali fungsi ni dipanggil semula sblm diluluskan.
-- Diuji live (BEGIN/ROLLBACK) — panggil 2x berturut dgn butiran berbeza, kunci
-- 'pelarasan' & jumlah kekal betul selepas panggilan kedua.
--
-- Turut backfill PV-2026-0103 (rekod SEDIA ADA yg terjejas) — tambah kunci
-- 'pelarasan':37.97 yg hilang, jumlah/upah tak berubah (dah betul).
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.cipta_baucar_harian(p_pekerja_id uuid, p_tarikh date DEFAULT NULL::date, p_jumlah double precision DEFAULT NULL::double precision, p_butiran jsonb DEFAULT NULL::jsonb)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_id text; v_no_siri text; v_sedia_id text; v_sedia_status text;
  v_upah double precision := 0; v_cash double precision := 0; v_baki double precision;
  v_bulan text; v_tarikh date;
  v_pelarasan_baharu double precision := 0; v_pelarasan_ids text[];
  v_pelarasan_sudah double precision := 0; v_pelarasan_total double precision := 0;
  v_butiran jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Log masuk diperlukan';
  END IF;
  IF NOT is_pemilik() AND p_pekerja_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Pekerja hanya boleh jana baucar harian untuk diri sendiri';
  END IF;

  v_tarikh := COALESCE(p_tarikh, (now() AT TIME ZONE 'Asia/Kuala_Lumpur')::date);
  v_bulan := to_char(v_tarikh, 'YYYY-MM');

  IF p_jumlah IS NOT NULL THEN
    v_upah := p_jumlah;
  ELSE
    SELECT COALESCE(SUM(
      (SELECT COALESCE(SUM((item->>'qty')::numeric * COALESCE(s.upah_pekerja, 0)), 0)
       FROM jsonb_array_elements(
         CASE WHEN t.kaedah_bayaran = 'consignment' AND NOT COALESCE(t.jualan_disahkan, false)
              THEN '[]'::jsonb
              ELSE COALESCE(t.items_terjual, t.items)
         END
       ) item
       LEFT JOIN stok s ON s.id = item->>'stokId')
    ), 0) INTO v_upah
    FROM transaksi t
    WHERE t.created_by = p_pekerja_id::text
      AND (t.tarikh_masa AT TIME ZONE 'Asia/Kuala_Lumpur')::date = v_tarikh;
  END IF;

  SELECT COALESCE(SUM(t.jumlah), 0) INTO v_cash
  FROM transaksi t
  WHERE t.created_by = p_pekerja_id::text
    AND (t.tarikh_masa AT TIME ZONE 'Asia/Kuala_Lumpur')::date = v_tarikh
    AND t.kaedah_bayaran = 'tunai' AND t.status = 'selesai';

  SELECT id, status INTO v_sedia_id, v_sedia_status FROM baucar_bayaran
    WHERE pekerja_id = p_pekerja_id AND kategori = 'upah_harian' AND tarikh = v_tarikh;

  -- Pelarasan BAHARU (belum pernah ditolak drpd mana-mana baucar lagi).
  SELECT COALESCE(SUM(jumlah_total), 0), COALESCE(array_agg(id), '{}')
    INTO v_pelarasan_baharu, v_pelarasan_ids
    FROM pelarasan_kos_pekerja WHERE pekerja_id = p_pekerja_id AND status = 'belum_diselaraskan';

  -- Pelarasan yg SUDAH terikat dgn baucar draf ni drpd panggilan SEBELUM ni (fix
  -- utama — elak "hilang" bila fungsi ni dipanggil > 1x utk hari/pekerja sama).
  IF v_sedia_id IS NOT NULL THEN
    SELECT COALESCE(SUM(jumlah_total), 0) INTO v_pelarasan_sudah
      FROM pelarasan_kos_pekerja WHERE baucar_id = v_sedia_id AND status = 'sudah_diselaraskan';
  END IF;

  v_pelarasan_total := v_pelarasan_baharu + v_pelarasan_sudah;
  v_upah := v_upah - v_pelarasan_total;

  v_baki := v_upah - v_cash;
  v_butiran := CASE WHEN v_pelarasan_total > 0 THEN COALESCE(p_butiran,'{}'::jsonb) || jsonb_build_object('pelarasan', v_pelarasan_total) ELSE p_butiran END;

  IF v_sedia_id IS NOT NULL THEN
    IF v_sedia_status = 'draf' THEN
      UPDATE baucar_bayaran SET jumlah = v_upah, cash_ditangan = v_cash, baki = v_baki, butiran = COALESCE(v_butiran, butiran)
        WHERE id = v_sedia_id;
      IF array_length(v_pelarasan_ids,1) > 0 THEN
        UPDATE pelarasan_kos_pekerja SET status='sudah_diselaraskan', baucar_id = v_sedia_id WHERE id = ANY(v_pelarasan_ids);
      END IF;
    END IF;
    RETURN v_sedia_id;
  END IF;

  v_id := gen_random_uuid()::text;
  v_no_siri := 'PV-' || extract(year from now())::text || '-' || lpad(nextval('baucar_siri_seq')::text, 4, '0');
  INSERT INTO baucar_bayaran (id, no_siri, pekerja_id, kategori, bulan, tarikh, jumlah, cash_ditangan, baki, tujuan, butiran)
  VALUES (v_id, v_no_siri, p_pekerja_id, 'upah_harian', v_bulan, v_tarikh, v_upah, v_cash, v_baki,
    'Upah harian ' || to_char(v_tarikh, 'DD/MM/YYYY'), v_butiran);
  IF array_length(v_pelarasan_ids,1) > 0 THEN
    UPDATE pelarasan_kos_pekerja SET status='sudah_diselaraskan', baucar_id = v_id WHERE id = ANY(v_pelarasan_ids);
  END IF;
  RETURN v_id;
END;
$function$;

-- Backfill PV-2026-0103 (Nadia, 3 Sep 2026) — pulih baris "pelarasan" yg hilang.
UPDATE baucar_bayaran
SET butiran = butiran || jsonb_build_object('pelarasan', 37.96812503609695)
WHERE id = 'a7acc395-0f4c-4426-b264-6fcdd2d02d39' AND NOT (butiran ? 'pelarasan');
