-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 148: Notifikasi Telegram bila pekerja THUMB IN (mula kerja)
-- + jadual pg_cron utk hantar "/laporan harian" (ringkasan penuh hari
-- SEMALAM) secara AUTOMATIK setiap pukul 8:00 pagi (waktu Malaysia) ke
-- semua chat pemilik yang aktif & notifikasi_aktif=true.
--
-- 1) THUMB IN — kehadiran dicipta (INSERT) SEKALI SAHAJA setiap sesi bila
--    pekerja tekan "Thumb In" (lihat thumbIn() di pengurusan.html). AFTER
--    INSERT jadi tepat: satu notifikasi setiap sesi kerja baharu, bukan
--    setiap kali baris kehadiran itu diubah (cth. bila thumb out nanti).
--    Guna saluran TELEGRAM SAHAJA (bukan emel/push) — makluman rutin 2x
--    sehari setiap pekerja tak sesuai bebankan emel/push pemilik; param
--    baharu "saluran":"telegram_sahaja" pada Edge Function
--    notifikasi-kelulusan-pemilik langkau terus ke bahagian Telegram.
--    (Thumb OUT sudah ada notifikasi — via baucar harian, SQL_TAMBAHAN_147.)
--
-- 2) LAPORAN HARIAN AUTOMATIK — pg_cron (sudah aktif di project ini,
--    versi 1.6.4) jadualkan '0 0 * * *' (00:00 UTC = 08:00 waktu Malaysia,
--    UTC+8 sepanjang tahun, tiada DST) panggil Edge Function
--    telegram-webhook?cron=laporan melalui pg_net. Endpoint tersebut
--    dikunci dgn header "x-cron-key" yg mesti padan secret Edge Function
--    BAHARU bernama CRON_LAPORAN_SECRET (PERLU DITETAPKAN oleh pemilik di
--    Supabase Dashboard > Edge Functions > Secrets — sila rujuk mesej
--    penghantaran fail utk nilai sebenar secret ini; TIDAK sama dgn
--    TELEGRAM_WEBHOOK_SECRET sedia ada, supaya endpoint cron ni berasingan
--    & tak berkongsi kunci dgn endpoint setup webhook).
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.notify_pemilik_thumb_in_baharu()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_nama text;
  v_butiran text;
BEGIN
  SELECT nama INTO v_nama FROM profiles WHERE id = NEW.pekerja_id;
  v_butiran := 'Mula kerja: ' || to_char(NEW.thumb_in_masa AT TIME ZONE 'Asia/Kuala_Lumpur', 'HH24:MI') ||
    ' (' || to_char(NEW.thumb_in_masa AT TIME ZONE 'Asia/Kuala_Lumpur', 'DD/MM/YYYY') || ')';

  PERFORM net.http_post(
    url := 'https://smepriytkoxkmpvjvvzq.supabase.co/functions/v1/notifikasi-kelulusan-pemilik',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNtZXByaXl0a294a21wdmp2dnpxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMzODE1OTcsImV4cCI6MjA5ODk1NzU5N30.bLDjFNZ_gMm9ufCkA4TeFbw1rysuLnlQN-qW_WW0zr8'
    ),
    body := jsonb_build_object(
      'jenis', '🟢 Pekerja Thumb In',
      'pekerja_nama', COALESCE(v_nama, '?'),
      'butiran', v_butiran,
      'saluran', 'telegram_sahaja'
    )
  );
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_notify_pemilik_thumb_in_baharu ON public.kehadiran;
CREATE TRIGGER trg_notify_pemilik_thumb_in_baharu
  AFTER INSERT ON public.kehadiran
  FOR EACH ROW
  EXECUTE FUNCTION notify_pemilik_thumb_in_baharu();

-- ── pg_cron: Laporan Harian automatik pukul 8 pagi (waktu Malaysia) ──
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'laporan-harian-8am') THEN
    PERFORM cron.unschedule('laporan-harian-8am');
  END IF;
END $$;

SELECT cron.schedule(
  'laporan-harian-8am',
  '0 0 * * *',
  $cron$
  SELECT net.http_post(
    url := 'https://smepriytkoxkmpvjvvzq.supabase.co/functions/v1/telegram-webhook?cron=laporan',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNtZXByaXl0a294a21wdmp2dnpxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMzODE1OTcsImV4cCI6MjA5ODk1NzU5N30.bLDjFNZ_gMm9ufCkA4TeFbw1rysuLnlQN-qW_WW0zr8',
      'x-cron-key', '576b98e42e21a27538e17db46fc9523ab448da904a4df5a7'
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 20000
  );
  $cron$
);
