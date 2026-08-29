-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 127: Notifikasi Pemilik — Permohonan Program Baharu
-- (pemohon_program: ejen/affiliate, penghantar, marketing)
--
-- PUNCA: pemohon_program (borang awam "Jadi Ejen/Affiliate", "Jadi
-- Penghantar", "Jadi Ejen Marketing" di index.html — sesiapa boleh mohon,
-- tiada log masuk) TIDAK PERNAH ada trigger notifikasi — beza drpd
-- permohonan_cuti/padam/bayaran_hutang/serahan_cash/serahan_produk yang
-- semua dah ada (SQL_TAMBAHAN_65/74/85/89). Akibatnya permohonan affiliate
-- baharu senyap masuk DB tanpa emel/push kpd pemilik — pemilik cuma
-- perasan bila buka semula tab "Permohonan Program" secara manual.
--
-- Guna edge function sedia ada notifikasi-kelulusan-pemilik (sama pattern
-- spt trigger lain) — tiada function/secret baharu diperlukan.
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.notify_pemilik_permohonan_program()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_jenis text;
  v_butiran text;
BEGIN
  v_jenis := 'Permohonan Program: ' || CASE NEW.jenis
    WHEN 'penghantar' THEN 'Penghantar'
    WHEN 'marketing' THEN 'Ejen Marketing (Affiliate)'
    WHEN 'ejen' THEN 'Ejen/Affiliate'
    ELSE NEW.jenis
  END;
  v_butiran := NEW.nama || ' — ' || NEW.telefon
    || COALESCE(' · Kawasan: ' || NEW.kawasan, '')
    || COALESCE(' · Produk: ' || NEW.nama_produk, '');

  PERFORM net.http_post(
    url := 'https://smepriytkoxkmpvjvvzq.supabase.co/functions/v1/notifikasi-kelulusan-pemilik',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNtZXByaXl0a294a21wdmp2dnpxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMzODE1OTcsImV4cCI6MjA5ODk1NzU5N30.bLDjFNZ_gMm9ufCkA4TeFbw1rysuLnlQN-qW_WW0zr8'
    ),
    body := jsonb_build_object('jenis', v_jenis, 'pekerja_nama', NEW.nama, 'butiran', v_butiran)
  );
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_notify_pemilik_permohonan_program ON pemohon_program;
CREATE TRIGGER trg_notify_pemilik_permohonan_program
AFTER INSERT ON pemohon_program
FOR EACH ROW EXECUTE FUNCTION public.notify_pemilik_permohonan_program();
