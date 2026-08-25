-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 119: Push/emel notifikasi bila ada TEMPAHAN PRE-ORDER
-- BAHARU masuk (pesan.html) — sambungan SQL_TAMBAHAN_118.
--
-- Sama pola: tiada trigger sedia ada pd pre_order yg sambung ke sistem
-- push (disahkan). Guna semula Edge Function notifikasi-kelulusan-pemilik
-- (dah dikemaskini sokong jenis='Pre-Order Baharu' dgn label "Kedai").
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.notify_pemilik_preorder_baru()
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
      'jenis', 'Pre-Order Baharu',
      'pekerja_nama', COALESCE(NEW.kedai_nama, '?'),
      'butiran', 'RM' || to_char(COALESCE(NEW.jumlah_selepas_diskaun, NEW.jumlah_asal, 0), 'FM999999990.00') || ' (' || COALESCE(NEW.bayar_metod,'?') || ') — #' || NEW.id
    )
  );
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_notify_pemilik_preorder_baru ON pre_order;
CREATE TRIGGER trg_notify_pemilik_preorder_baru
  AFTER INSERT ON public.pre_order
  FOR EACH ROW EXECUTE FUNCTION notify_pemilik_preorder_baru();
