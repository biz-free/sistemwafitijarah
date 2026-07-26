-- SQL_TAMBAHAN_55: Baiki sempadan hari UTC vs waktu Malaysia (UTC+8)
--
-- BUG: Pangkalan data berjalan pada UTC (SHOW timezone = UTC), tetapi
-- perniagaan beroperasi waktu Malaysia (UTC+8). Semua kiraan "hari ini"
-- yang guna CURRENT_DATE / tarikh_masa::date sebenarnya guna sempadan hari
-- UTC — jadi apa-apa yang berlaku antara 12:00 tengah malam – 8:00 pagi
-- waktu Malaysia tersalah dikira sebagai HARI SEBELUMNYA.
--
-- Kesan sebenar yang dikesan: pekerja yang thumb in 7:36 pagi (= 23:36 UTC
-- hari sebelumnya) langsung tak muncul dalam Status Live ("Belum thumb in"
-- walaupun sedang bekerja), dan jualan/upah awal pagi tersalah hari.
--
-- Pembetulan: tukar semua sempadan hari kepada (ts AT TIME ZONE
-- 'Asia/Kuala_Lumpur')::date. Malaysia tiada DST (kekal UTC+8) jadi
-- penukaran ini stabil sepanjang tahun.

CREATE OR REPLACE FUNCTION public.papan_jualan_pekerja_hari_ini()
RETURNS TABLE(pekerja_id uuid, nama text, jumlah_jualan double precision, bilangan_transaksi bigint)
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT p.id, p.nama,
    COALESCE(SUM(t.jumlah) FILTER (WHERE t.status = 'selesai'), 0) AS jumlah_jualan,
    COUNT(t.id) FILTER (WHERE t.status = 'selesai') AS bilangan_transaksi
  FROM profiles p
  LEFT JOIN transaksi t
    ON t.created_by = p.id::text
   AND (t.tarikh_masa AT TIME ZONE 'Asia/Kuala_Lumpur')::date
       = (now() AT TIME ZONE 'Asia/Kuala_Lumpur')::date
  WHERE p.role = 'pekerja'
  GROUP BY p.id, p.nama
  ORDER BY jumlah_jualan DESC, p.nama;
$function$;

GRANT EXECUTE ON FUNCTION public.papan_jualan_pekerja_hari_ini() TO authenticated;

CREATE OR REPLACE FUNCTION public.cipta_baucar_harian(
  p_pekerja_id uuid, p_tarikh date DEFAULT NULL::date,
  p_jumlah double precision DEFAULT NULL::double precision,
  p_butiran jsonb DEFAULT NULL::jsonb
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_id text; v_no_siri text; v_sedia_id text;
  v_upah double precision := 0; v_cash double precision := 0; v_baki double precision;
  v_bulan text; v_tarikh date;
BEGIN
  IF NOT is_pemilik() THEN
    RAISE EXCEPTION 'Hanya pemilik boleh jana baucar harian';
  END IF;

  -- Default = HARI INI waktu Malaysia (bukan CURRENT_DATE yang ikut UTC).
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

  v_baki := v_upah - v_cash;

  SELECT id INTO v_sedia_id FROM baucar_bayaran
    WHERE pekerja_id = p_pekerja_id AND kategori = 'upah_harian' AND tarikh = v_tarikh;

  IF v_sedia_id IS NOT NULL THEN
    UPDATE baucar_bayaran SET jumlah = v_upah, cash_ditangan = v_cash, baki = v_baki,
      butiran = COALESCE(p_butiran, butiran)
      WHERE id = v_sedia_id AND status = 'draf';
    RETURN v_sedia_id;
  END IF;

  v_id := gen_random_uuid()::text;
  v_no_siri := 'PV-' || extract(year from now())::text || '-' || lpad(nextval('baucar_siri_seq')::text, 4, '0');
  INSERT INTO baucar_bayaran (id, no_siri, pekerja_id, kategori, bulan, tarikh, jumlah, cash_ditangan, baki, tujuan, butiran)
  VALUES (v_id, v_no_siri, p_pekerja_id, 'upah_harian', v_bulan, v_tarikh, v_upah, v_cash, v_baki,
    'Upah harian ' || to_char(v_tarikh, 'DD/MM/YYYY'), p_butiran);
  RETURN v_id;
END;
$function$;
