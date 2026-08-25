-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 121: GUGURKAN sepenuhnya sistem "Kod Referral Bawa Kawan"
-- (kod rujukan no. telefon) — digantikan oleh Sistem Affiliate (Google
-- OAuth) yang lebih sistematik.
--
-- PEMUSNAHAN KEKAL — padam jadual/lajur/fungsi/cron berkaitan. Data
-- sejarah ganjaran (rujukan_ganjaran) & senarai nombor manual
-- (rujukan_manual) akan HILANG SELEPAS INI, tiada cara pulih.
-- Disahkan oleh pemilik sebelum dijalankan.
-- ═══════════════════════════════════════════════════════════

-- 1. Henti & padam cron job (jalan setiap 15 minit)
SELECT cron.unschedule('rujukan-ganjaran-setiap-15-minit');

-- 2. Kemaskini trigger checkout kongsi (buang cabang kod_rujukan,
--    kekalkan voucher + affiliate sahaja).
CREATE OR REPLACE FUNCTION public.validasi_harga_pesanan_edagang()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  item jsonb;
  item_baru jsonb := '[]'::jsonb;
  harga_sebenar float;
  sub float := 0;
  kos_min float := 0;
  v_check RECORD;
  v_affiliate RECORD;
  v_bil_kod int;
BEGIN
  v_bil_kod := (CASE WHEN NEW.kod_baucar IS NOT NULL AND NEW.kod_baucar <> '' THEN 1 ELSE 0 END)
             + (CASE WHEN NEW.kod_affiliate IS NOT NULL AND NEW.kod_affiliate <> '' THEN 1 ELSE 0 END);
  IF v_bil_kod > 1 THEN
    RAISE EXCEPTION 'Hanya satu promosi dibenarkan setiap pesanan — sila guna kod voucher ATAU kod affiliate sahaja';
  END IF;

  FOR item IN SELECT * FROM jsonb_array_elements(COALESCE(NEW.items, '[]'::jsonb)) LOOP
    SELECT harga_jual INTO harga_sebenar FROM stok WHERE id = item->>'stokId';
    IF harga_sebenar IS NULL THEN
      RAISE EXCEPTION 'Produk % tidak wujud atau telah dipadam', item->>'stokId';
    END IF;
    item_baru := item_baru || jsonb_build_object(
      'stokId', item->>'stokId',
      'nama', item->>'nama',
      'unit', item->>'unit',
      'harga', harga_sebenar,
      'qty', (item->>'qty')::int
    );
    sub := sub + harga_sebenar * (item->>'qty')::int;
  END LOOP;

  NEW.items := item_baru;
  NEW.subjumlah := sub;

  SELECT MIN(kadar_asas) INTO kos_min FROM zon_penghantaran;
  IF NEW.kos_penghantaran IS NULL OR NEW.kos_penghantaran < COALESCE(kos_min, 0) THEN
    NEW.kos_penghantaran := COALESCE(kos_min, 0);
  END IF;

  IF NEW.kod_baucar IS NOT NULL AND NEW.kod_baucar <> '' THEN
    SELECT * INTO v_check FROM validasi_baucar(NEW.kod_baucar, NEW.pelanggan_telefon, sub);
    IF NOT v_check.sah THEN
      RAISE EXCEPTION '%', v_check.mesej;
    END IF;
    NEW.diskaun := v_check.diskaun;
    NEW.kod_baucar := upper(trim(NEW.kod_baucar));
    IF v_check.percuma_penghantaran THEN
      NEW.kos_penghantaran := 0;
    END IF;
    UPDATE baucar SET bilangan_guna = bilangan_guna + 1 WHERE kod = NEW.kod_baucar;
    INSERT INTO baucar_guna (kod, telefon, pesanan_id) VALUES (NEW.kod_baucar, NEW.pelanggan_telefon, NEW.id);
  ELSE
    NEW.diskaun := 0;
  END IF;

  IF NEW.kod_affiliate IS NOT NULL AND NEW.kod_affiliate <> '' THEN
    SELECT * INTO v_affiliate FROM validasi_kod_affiliate(NEW.kod_affiliate, NEW.pelanggan_telefon, sub);
    IF NOT v_affiliate.sah THEN
      RAISE EXCEPTION '%', v_affiliate.mesej;
    END IF;
    NEW.kod_affiliate := upper(trim(NEW.kod_affiliate));
    NEW.affiliate_diskaun := ROUND((sub * v_affiliate.diskaun_peratus / 100)::numeric, 2);
  ELSE
    NEW.affiliate_diskaun := 0;
  END IF;

  NEW.jumlah := sub + NEW.kos_penghantaran - COALESCE(NEW.diskaun, 0) - COALESCE(NEW.affiliate_diskaun, 0);
  NEW.status_bayaran := 'menunggu';

  RETURN NEW;
END;
$function$;

-- 3. Padam fungsi rujukan (tiada apa-apa lagi memanggilnya selepas #2)
DROP FUNCTION IF EXISTS public.validasi_rujukan(text, text);
DROP FUNCTION IF EXISTS public.semak_ganjaran_rujukan_saya(text);

-- 3b. Buang rujukan cron dari senarai dipantau semak_kesihatan_sistem()
--     (job dah tak wujud lepas langkah #1, ini cuma bersihkan kod mati)
CREATE OR REPLACE FUNCTION public.semak_kesihatan_sistem()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_cron jsonb;
BEGIN
  IF NOT is_pemilik() THEN RAISE EXCEPTION 'Hanya pemilik boleh semak status sistem'; END IF;

  SELECT jsonb_agg(jsonb_build_object(
    'jobname', j.jobname,
    'last_run', r.start_time,
    'status', r.status,
    'terlajak', CASE
      WHEN r.start_time IS NULL THEN true
      WHEN j.jobname = 'susulan-bayaran-harian' THEN r.start_time < now() - interval '26 hours'
      WHEN j.jobname = 'kempen-winback-mingguan' THEN r.start_time < now() - interval '8 days'
      ELSE false
    END
  ) ORDER BY j.jobid)
  INTO v_cron
  FROM cron.job j
  LEFT JOIN LATERAL (
    SELECT start_time, status FROM cron.job_run_details d
    WHERE d.jobid = j.jobid ORDER BY d.start_time DESC LIMIT 1
  ) r ON true
  WHERE j.jobname IN ('susulan-bayaran-harian','kempen-winback-mingguan');

  RETURN jsonb_build_object(
    'masa_server', now(),
    'jumlah_pekerja_aktif', (SELECT count(*) FROM profiles WHERE role='pekerja' AND status='aktif'),
    'jumlah_kedai', (SELECT count(*) FROM kedai),
    'jumlah_produk_aktif', (SELECT count(*) FROM stok WHERE aktif IS NOT FALSE),
    'cron', COALESCE(v_cron, '[]'::jsonb)
  );
END;
$function$;

-- 4. Padam jadual (CASCADE buang dasar RLS & indeks berkaitan sekali)
DROP TABLE IF EXISTS rujukan_ganjaran CASCADE;
DROP TABLE IF EXISTS rujukan_manual CASCADE;

-- 5. Padam lajur pada pesanan_edagang & tetapan
ALTER TABLE pesanan_edagang DROP COLUMN IF EXISTS kod_rujukan;
ALTER TABLE pesanan_edagang DROP COLUMN IF EXISTS rujukan_diskaun;
ALTER TABLE tetapan DROP COLUMN IF EXISTS rujukan_aktif;
ALTER TABLE tetapan DROP COLUMN IF EXISTS rujukan_diskaun_kawan_peratus;
ALTER TABLE tetapan DROP COLUMN IF EXISTS rujukan_ganjaran_rm;
ALTER TABLE tetapan DROP COLUMN IF EXISTS rujukan_luput_hari;
