-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 74: Asingkan saluran notifikasi pemilik ikut sumber
-- permohonan "Ambil Stok" —
--   - Ambil Stok (butang tunggal, kad Stok Bawaan Saya, perlu Thumb
--     In) → EMEL (macam sedia ada, trigger notify_pemilik_kelulusan
--     tak berubah utk laluan ni — sebab kekal NULL).
--   - Request Stok Mobile (borang berbilang produk, Tab Stok >
--     Mobile, boleh tanpa Thumb In) → WHATSAPP sahaja (client-side,
--     lihat hantarRequestStokMobile()), BUKAN emel — elak pemilik
--     terima 2 notifikasi berlainan saluran utk 1 tindakan yang sama.
--
-- Pembeza: Request Stok Mobile SENTIASA isi medan "sebab" (nota
-- tarikh/masa pick up dijadualkan — lihat SQL_TAMBAHAN_73), manakala
-- Ambil Stok single-item TIDAK PERNAH hantar p_sebab (kekal NULL).
-- Guna "sebab IS NOT NULL" sebagai penanda sumber, tiada lajur/RPC
-- baharu diperlukan.
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.notify_pemilik_kelulusan()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
  v_pekerja_nama text;
  v_jenis text;
  v_butiran text;
BEGIN
  IF TG_TABLE_NAME = 'serahan_produk' AND NEW.status <> 'menunggu' THEN
    RETURN NEW;
  END IF;

  -- Request Stok Mobile — notifikasi via WhatsApp (client-side), bukan emel.
  IF TG_TABLE_NAME = 'serahan_produk' AND NEW.jenis = 'ambil' AND NEW.sebab IS NOT NULL THEN
    RETURN NEW;
  END IF;

  SELECT nama INTO v_pekerja_nama FROM profiles WHERE id = NEW.pekerja_id;

  IF TG_TABLE_NAME = 'permohonan_padam' THEN
    v_jenis := 'Permohonan Padam';
    v_butiran := COALESCE(NEW.rekod_label, NEW.jenis) || COALESCE(' — Sebab: ' || NEW.sebab, '');
  ELSIF TG_TABLE_NAME = 'permohonan_cuti' THEN
    v_jenis := 'Permohonan Cuti/MC/Off';
    v_butiran := NEW.jenis || ' (' || to_char(NEW.tarikh_mula,'DD/MM/YYYY') || ' - ' || to_char(NEW.tarikh_tamat,'DD/MM/YYYY') || ')';
  ELSIF TG_TABLE_NAME = 'serahan_cash' THEN
    v_jenis := 'Serahan Duit Cash';
    v_butiran := 'RM' || NEW.jumlah;
  ELSIF TG_TABLE_NAME = 'serahan_produk' THEN
    v_jenis := CASE WHEN NEW.jenis = 'ambil' THEN 'Permohonan Ambil Stok' ELSE 'Serahan Produk Reject' END;
    v_butiran := NEW.stok_nama || ' ×' || NEW.kuantiti;
  ELSE
    RETURN NEW;
  END IF;

  PERFORM net.http_post(
    url := 'https://smepriytkoxkmpvjvvzq.supabase.co/functions/v1/notifikasi-kelulusan-pemilik',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNtZXByaXl0a294a21wdmp2dnpxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMzODE1OTcsImV4cCI6MjA5ODk1NzU5N30.bLDjFNZ_gMm9ufCkA4TeFbw1rysuLnlQN-qW_WW0zr8'
    ),
    body := jsonb_build_object('jenis', v_jenis, 'pekerja_nama', COALESCE(v_pekerja_nama, '?'), 'butiran', v_butiran)
  );
  RETURN NEW;
END;
$function$;
