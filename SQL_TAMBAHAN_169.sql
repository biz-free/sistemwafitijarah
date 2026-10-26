-- ============================================================
-- SQL TAMBAHAN 169: Baucar upah harian kira tunai kutipan hutang (permohonan_bayaran_hutang)
-- Hasil semakan baucar Nadia 26 Okt 2026: cipta_baucar_harian hanya menjumlah transaksi
-- tunai selesai, tetapi kira_cash_dipegang_pekerja juga mengira bayaran hutang tunai yang
-- disahkan. Akibatnya baucar hari itu tunjuk baki +RM14.82 (syarikat bayar pekerja)
-- sedangkan pekerja pegang RM134 duit syarikat (sepatutnya baki -RM119.18).
-- Jumlah UPAH tidak berubah; hanya cash_ditangan & baki.
--
--  A. cipta_baucar_harian: v_cash += bayaran hutang tunai DISAHKAN pada tarikh yang sama
--     (tarikh ikut created_at waktu Malaysia, SAMA dgn kira_cash_dipegang_pekerja).
--  B. Betulkan 1 baris baucar draf Nadia 26 Okt (PK WHERE, hanya jika masih 'draf').
-- ============================================================

-- ---------- A ----------
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

  -- BAHARU (SQL 169): kutipan hutang tunai yg sudah disahkan pemilik, sama dgn kira_cash_dipegang_pekerja
  v_cash := v_cash + COALESCE((
    SELECT SUM(p.jumlah) FROM permohonan_bayaran_hutang p
    WHERE p.pekerja_id = p_pekerja_id AND p.kaedah_bayaran = 'tunai' AND p.status = 'disahkan'
      AND (p.created_at AT TIME ZONE 'Asia/Kuala_Lumpur')::date = v_tarikh
  ), 0);

  SELECT id, status INTO v_sedia_id, v_sedia_status FROM baucar_bayaran
    WHERE pekerja_id = p_pekerja_id AND kategori = 'upah_harian' AND tarikh = v_tarikh;

  SELECT COALESCE(SUM(jumlah_total), 0), COALESCE(array_agg(id), '{}')
    INTO v_pelarasan_baharu, v_pelarasan_ids
    FROM pelarasan_kos_pekerja WHERE pekerja_id = p_pekerja_id AND status = 'belum_diselaraskan';

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

-- ---------- B: betulkan 1 baris (baucar draf Nadia 26/10/2026) ----------
-- Dijangka: cash_ditangan 24.5 -> 158.5, baki 14.82 -> -119.18. Jumlah baucar TIDAK berubah.
UPDATE baucar_bayaran b SET
  cash_ditangan = b.cash_ditangan + p.tambah,
  baki = b.jumlah - (b.cash_ditangan + p.tambah)
FROM (SELECT COALESCE(SUM(jumlah), 0) AS tambah FROM permohonan_bayaran_hutang
      WHERE pekerja_id = (SELECT pekerja_id FROM baucar_bayaran WHERE id = 'ecc125ba-6714-4c30-9c00-4844c4bb1b91')
        AND kaedah_bayaran = 'tunai' AND status = 'disahkan'
        AND (created_at AT TIME ZONE 'Asia/Kuala_Lumpur')::date = DATE '2026-10-26') p
WHERE b.id = 'ecc125ba-6714-4c30-9c00-4844c4bb1b91' AND b.status = 'draf' AND b.cash_ditangan = 24.5;

-- Pengesahan (SELECT sahaja):
--   select jumlah, cash_ditangan, baki, status from baucar_bayaran where id='ecc125ba-6714-4c30-9c00-4844c4bb1b91';
