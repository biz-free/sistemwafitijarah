-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 145: Push/emel notifikasi kpd pemilik bila PEKERJA rekod
-- tempahan/penghantaran BAHARU guna kaedah "Online Transfer" — supaya
-- pemilik ingat utk SEMAK dahulu sama ada duit sudah benar-benar masuk
-- akaun bank syarikat atau belum, sebelum anggap transaksi tu sah/selesai
-- (tiada pengesahan automatik bank dalam sistem ni — pekerja cuma tandakan
-- kaedah bayaran, bukan bukti bank masuk).
--
-- Guna semula Edge Function notifikasi-kelulusan-pemilik sedia ada (dah
-- generik terima sebarang `jenis`/`pekerja_nama`/`butiran` — lihat
-- SQL_TAMBAHAN_65/118/119 utk corak yg sama). Fire AFTER INSERT sahaja
-- (tempahan BAHARU) — bukan bila pemilik sendiri tukar kaedah bayaran
-- transaksi sedia ada ke Transfer (tukar_kaedah_bayaran_transaksi, SQL_
-- TAMBAHAN 90/91), sebab tu tindakan pemilik sendiri, bukan sesuatu yg
-- pemilik perlu dimaklumkan.
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.notify_pemilik_transfer_baru()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_nama_pekerja text;
  v_nama_kedai text;
BEGIN
  SELECT nama INTO v_nama_pekerja FROM profiles WHERE id::text = NEW.created_by;
  IF NEW.kedai_id IS NOT NULL THEN
    SELECT nama INTO v_nama_kedai FROM kedai WHERE id = NEW.kedai_id;
  END IF;

  PERFORM net.http_post(
    url := 'https://smepriytkoxkmpvjvvzq.supabase.co/functions/v1/notifikasi-kelulusan-pemilik',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNtZXByaXl0a294a21wdmp2dnpxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMzODE1OTcsImV4cCI6MjA5ODk1NzU5N30.bLDjFNZ_gMm9ufCkA4TeFbw1rysuLnlQN-qW_WW0zr8'
    ),
    body := jsonb_build_object(
      'jenis', '💳 Tempahan Online Transfer Baharu — Sila Semak Bank',
      'pekerja_nama', COALESCE(v_nama_pekerja, '?'),
      'butiran', COALESCE(v_nama_kedai, 'Tiada nama kedai/pelanggan') || ' — RM' || to_char(NEW.jumlah, 'FM999999990.00')
        || ' — #' || COALESCE(NEW.resit, NEW.id)
        || E'\nSila sahkan duit SUDAH masuk akaun bank syarikat sebelum anggap transaksi ini selesai.'
    )
  );
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_notify_pemilik_transfer_baru ON transaksi;
CREATE TRIGGER trg_notify_pemilik_transfer_baru
  AFTER INSERT ON public.transaksi
  FOR EACH ROW WHEN (NEW.kaedah_bayaran = 'transfer')
  EXECUTE FUNCTION notify_pemilik_transfer_baru();
