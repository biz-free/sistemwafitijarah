-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 151: Kad Telegram "Duit Masuk / Belum Masuk" utk tempahan
-- Online Transfer + pemakluman ke kumpulan WhatsApp Team Sales.
--
-- Sebelum ini mesej "Tempahan Online Transfer Baharu — Sila Semak Bank"
-- (SQL 145) hanya teks, tiada butang. Kini mesej itu ada 2 butang:
--   ✅ Duit Masuk   -> pemilik sahkan duit SUDAH masuk akaun bank
--   ✕ Belum Masuk   -> duit BELUM masuk (pekerja/jualan perlu susul)
-- Keputusan diedit pada mesej Telegram dan direkod ke
-- private.pemakluman_kelulusan (SQL 150) supaya skrip VPS menghantarnya ke
-- kumpulan WhatsApp Team Sales.
--
-- PENTING: keputusan ini TIDAK mengubah jadual transaksi (status/hutang/stok
-- kekal). Ia hanya pengesahan + pemakluman. Diputuskan SEKALI sahaja per
-- transaksi (semakan pada private.pemakluman_kelulusan).
--
-- Tiada jadual/lajur baharu. Perlu deploy semula 2 Edge Function:
-- notifikasi-kelulusan-pemilik dan telegram-webhook (kod dlm repo).
-- ═══════════════════════════════════════════════════════════

-- 1. Fungsi keputusan (dipanggil telegram-webhook, service_role sahaja)
CREATE OR REPLACE FUNCTION public.telegram_putuskan_transfer(p_admin_chat_id bigint, p_id text, p_status text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
DECLARE
  v_admin_user_id uuid;
  v_tx RECORD;
BEGIN
  SELECT user_id INTO v_admin_user_id FROM telegram_admin WHERE chat_id = p_admin_chat_id AND aktif = true;
  IF v_admin_user_id IS NULL THEN
    RAISE EXCEPTION 'Chat Telegram ini tidak didaftarkan sebagai pemilik atau tidak aktif';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = v_admin_user_id AND role = 'pemilik') THEN
    RAISE EXCEPTION 'Akaun berkaitan bukan pemilik';
  END IF;
  IF p_status NOT IN ('disahkan','ditolak') THEN
    RAISE EXCEPTION 'Status tidak sah: %', p_status;
  END IF;

  SELECT id, jumlah, resit, kaedah_bayaran INTO v_tx FROM transaksi WHERE id = p_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Transaksi tidak dijumpai (mungkin sudah dipadam)'; END IF;
  IF v_tx.kaedah_bayaran <> 'transfer' THEN RAISE EXCEPTION 'Transaksi ini bukan Online Transfer'; END IF;
  IF EXISTS (SELECT 1 FROM private.pemakluman_kelulusan WHERE jadual = 'transaksi' AND rekod_id = p_id) THEN
    RAISE EXCEPTION 'Transfer ini sudah diputuskan sebelum ini';
  END IF;

  RETURN 'Online Transfer RM' || to_char(v_tx.jumlah, 'FM999999990.00') || ' #' || COALESCE(v_tx.resit, v_tx.id) || ' — '
    || CASE WHEN p_status = 'disahkan' THEN 'DUIT SUDAH MASUK bank ✅' ELSE 'DUIT BELUM MASUK bank ✕' END;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.telegram_putuskan_transfer(bigint, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.telegram_putuskan_transfer(bigint, text, text) TO service_role;

-- 2. Pencetus (SQL 145) kini hantar record_id + jenis_rekod supaya mesej ada butang
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
      'record_id', NEW.id,
      'jenis_rekod', 'transaksi',
      'pekerja_nama', COALESCE(v_nama_pekerja, '?'),
      'butiran', COALESCE(v_nama_kedai, 'Tiada nama kedai/pelanggan') || ' — RM' || to_char(NEW.jumlah, 'FM999999990.00')
        || ' — #' || COALESCE(NEW.resit, NEW.id)
        || E'\nSila sahkan duit SUDAH masuk akaun bank syarikat sebelum anggap transaksi ini selesai.'
    )
  );
  RETURN NEW;
END;
$function$;
