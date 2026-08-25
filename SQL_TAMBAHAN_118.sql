-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 118: Push/emel notifikasi bila TEMPAHAN E-DAGANG BAHARU masuk
--
-- Punca aduan: pemilik tak dapat push notification bila ada tempahan baru
-- e-dagang (index.html/pesan.html) masuk. Disahkan — ciri ni memang tak
-- pernah wujud (tiada trigger pd pesanan_edagang yg sambung ke sistem push
-- sedia ada). Sistem push sedia ada (notify_pemilik_kelulusan, SQL_TAMBAHAN_65)
-- cuma disambung pd 5 jadual permohonan pekerja (padam/cuti/serahan cash/
-- serahan produk/bayar hutang) — bukan pesanan pelanggan.
--
-- Guna semula Edge Function notifikasi-kelulusan-pemilik (dah dikemaskini
-- sokong jenis='Tempahan E-Dagang Baharu' dgn wording & label sesuai jualan,
-- bukan "perlu kelulusan"). Fire AFTER INSERT — setiap tempahan baharu
-- (tak kira kaedah bayar) push+emel semua pemilik serta-merta.
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.notify_pemilik_pesanan_baru()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM net.http_post(
    url := 'https://smepriytkoxkmpvjvvzq.supabase.co/functions/v1/notifikasi-kelulusan-pemilik',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNtZXByaXl0a294a21wdmp2dnpxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMzODE1OTcsImV4cCI6MjA5ODk1NzU5N30.bLDjFNZ_gMm9ufCkA4TeFbw1rysuLnlQN-qW_WW0zr8'
    ),
    body := jsonb_build_object(
      'jenis', 'Tempahan E-Dagang Baharu',
      'pekerja_nama', COALESCE(NEW.pelanggan_nama, '?'),
      'butiran', 'RM' || to_char(NEW.jumlah, 'FM999999990.00') || ' (' || COALESCE(NEW.kaedah_bayaran,'?') || ') — #' || NEW.id
    )
  );
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_notify_pemilik_pesanan_baru ON pesanan_edagang;
CREATE TRIGGER trg_notify_pemilik_pesanan_baru
  AFTER INSERT ON public.pesanan_edagang
  FOR EACH ROW EXECUTE FUNCTION notify_pemilik_pesanan_baru();
