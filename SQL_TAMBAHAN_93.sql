-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 93: Pemilik minta indicator "Status Sistem" di
-- Tetapan — semakan pantas sambungan DB, bilangan rekod asas &
-- status automasi (cron) terkini, supaya boleh nampak dgn cepat
-- kalau ada bahagian sistem yang senyap rosak/berhenti.
--
-- Cron job yang wujud (disahkan via cron.job):
--   1. rujukan-ganjaran-setiap-15-minit (*/15 * * * *)  — buffer lewat 20 min
--   2. susulan-bayaran-harian (0 2 * * *, harian 2am)   — buffer lewat 26 jam
--   3. kempen-winback-mingguan (0 3 * * 1, Isnin 3am)   — buffer lewat 8 hari
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.semak_kesihatan_sistem()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
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
      WHEN j.jobname = 'rujukan-ganjaran-setiap-15-minit' THEN r.start_time < now() - interval '20 minutes'
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
  WHERE j.jobname IN ('rujukan-ganjaran-setiap-15-minit','susulan-bayaran-harian','kempen-winback-mingguan');

  RETURN jsonb_build_object(
    'masa_server', now(),
    'jumlah_pekerja_aktif', (SELECT count(*) FROM profiles WHERE role='pekerja' AND status='aktif'),
    'jumlah_kedai', (SELECT count(*) FROM kedai),
    'jumlah_produk_aktif', (SELECT count(*) FROM stok WHERE aktif IS NOT FALSE),
    'cron', COALESCE(v_cron, '[]'::jsonb)
  );
END;
$function$;
