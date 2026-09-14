-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 147: Notifikasi pemilik bila PEKERJA thumb out — baucar
-- harian (upah_harian) baharu dijana secara automatik (draf) & PERLU
-- disemak/diluluskan pemilik. Susulan SQL_TAMBAHAN_146 (integrasi
-- Telegram) — notifikasi ni hantar ke emel+push+Telegram (guna semula
-- Edge Function notifikasi-kelulusan-pemilik), DAN pemilik boleh terus
-- "✅ Lulus / ✕ Batal" baucar tu dari Telegram (tambah jadual
-- 'baucar_bayaran' ke dispatcher telegram_putuskan()).
--
-- KENAPA AFTER INSERT SAHAJA (bukan UPDATE): cipta_baucar_harian() (RPC
-- dipanggil bila pekerja thumb out — lihat janaBaucarHarianAutomatik()
-- di pengurusan.html) buat INSERT baharu HANYA pd thumb-out PERTAMA utk
-- hari/pekerja tu; panggilan berikutnya (cth transaksi diedit lepas tu)
-- cuma UPDATE baris draf SEDIA ADA. AFTER INSERT jadi tepat — SATU
-- notifikasi setiap kali baucar harian BAHARU muncul, tak spam pemilik
-- bila jumlah dikira semula.
--
-- NOTA status baucar_bayaran: draf/diluluskan/dibayar/dibatalkan (BUKAN
-- disahkan/ditolak spt 4 jadual lain dlm telegram_putuskan()) — jadi
-- cawangan 'baucar_bayaran' di bawah memetakan A→'diluluskan',
-- R→'dibatalkan', dan cuma bertindak jika baucar MASIH 'draf' (elak
-- Telegram terlanjur ubah baucar yg dah dibayar/diluluskan pemilik
-- sendiri melalui Sistem Pengurusan).
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.notify_pemilik_baucar_harian_baharu()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_nama text;
  v_butiran text;
BEGIN
  IF NEW.kategori <> 'upah_harian' THEN
    RETURN NEW;
  END IF;

  SELECT nama INTO v_nama FROM profiles WHERE id = NEW.pekerja_id;
  v_butiran := to_char(NEW.tarikh, 'DD/MM/YYYY')
    || ' — Upah RM' || to_char(COALESCE(NEW.jumlah,0), 'FM999999990.00')
    || ' | Cash tangan RM' || to_char(COALESCE(NEW.cash_ditangan,0), 'FM999999990.00')
    || ' | Baki serah RM' || to_char(COALESCE(NEW.baki,0), 'FM999999990.00');

  PERFORM net.http_post(
    url := 'https://smepriytkoxkmpvjvvzq.supabase.co/functions/v1/notifikasi-kelulusan-pemilik',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNtZXByaXl0a294a21wdmp2dnpxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMzODE1OTcsImV4cCI6MjA5ODk1NzU5N30.bLDjFNZ_gMm9ufCkA4TeFbw1rysuLnlQN-qW_WW0zr8'
    ),
    body := jsonb_build_object(
      'jenis', '🕐 Pekerja Thumb Out — Baucar Harian Perlu Disemak',
      'pekerja_nama', COALESCE(v_nama, '?'),
      'butiran', v_butiran,
      'record_id', NEW.id,
      'jenis_rekod', 'baucar_bayaran'
    )
  );
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_notify_pemilik_baucar_harian_baharu ON public.baucar_bayaran;
CREATE TRIGGER trg_notify_pemilik_baucar_harian_baharu
  AFTER INSERT ON public.baucar_bayaran
  FOR EACH ROW WHEN (NEW.kategori = 'upah_harian')
  EXECUTE FUNCTION notify_pemilik_baucar_harian_baharu();

-- ── Tambah jadual 'baucar_bayaran' ke dispatcher Telegram (SQL_TAMBAHAN_146) ──
-- CREATE OR REPLACE penuh (Postgres tiada "ADD BRANCH") — 4 cawangan asal
-- (serahan_cash/permohonan_cuti/permohonan_bayaran_hutang/serahan_produk)
-- KEKAL SAMA, cuma tambah cawangan baucar_bayaran di hujung.
CREATE OR REPLACE FUNCTION public.telegram_putuskan(p_admin_chat_id bigint, p_jadual text, p_id text, p_status text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_admin_user_id uuid;
  v_ok boolean;
  v_row RECORD;
  v_baki double precision;
  t RECORD;
BEGIN
  SELECT user_id INTO v_admin_user_id FROM telegram_admin WHERE chat_id = p_admin_chat_id AND aktif = true;
  IF v_admin_user_id IS NULL THEN
    RAISE EXCEPTION 'Chat Telegram ini tidak didaftarkan sebagai pemilik atau tidak aktif';
  END IF;
  SELECT EXISTS(SELECT 1 FROM profiles WHERE id = v_admin_user_id AND role = 'pemilik') INTO v_ok;
  IF NOT v_ok THEN
    RAISE EXCEPTION 'Akaun berkaitan bukan pemilik';
  END IF;
  IF p_status NOT IN ('disahkan','ditolak') THEN
    RAISE EXCEPTION 'Status tidak sah: %', p_status;
  END IF;

  IF p_jadual = 'serahan_cash' THEN
    UPDATE serahan_cash SET status = p_status, disahkan_oleh = v_admin_user_id, disahkan_pada = now()
      WHERE id = p_id AND status = 'menunggu';
    IF NOT FOUND THEN RAISE EXCEPTION 'Rekod tidak dijumpai atau sudah diputuskan'; END IF;
    RETURN 'Serahan cash ' || CASE WHEN p_status='disahkan' THEN 'disahkan ✅' ELSE 'ditolak ✕' END;

  ELSIF p_jadual = 'permohonan_cuti' THEN
    UPDATE permohonan_cuti SET status = p_status WHERE id = p_id AND status = 'menunggu';
    IF NOT FOUND THEN RAISE EXCEPTION 'Rekod tidak dijumpai atau sudah diputuskan'; END IF;
    RETURN 'Permohonan cuti/MC/off ' || CASE WHEN p_status='disahkan' THEN 'diluluskan ✅' ELSE 'ditolak ✕' END;

  ELSIF p_jadual = 'permohonan_bayaran_hutang' THEN
    SELECT * INTO v_row FROM permohonan_bayaran_hutang WHERE id = p_id AND status = 'menunggu';
    IF NOT FOUND THEN RAISE EXCEPTION 'Rekod tidak dijumpai atau sudah diputuskan'; END IF;

    IF p_status = 'disahkan' THEN
      IF v_row.kedai_id IS NOT NULL THEN
        IF v_row.settlement_penuh THEN
          UPDATE kedai SET hutang = 0 WHERE id = v_row.kedai_id;
          UPDATE transaksi SET status = 'selesai' WHERE kedai_id = v_row.kedai_id AND status = 'hutang';
        ELSE
          UPDATE kedai SET hutang = GREATEST(0, hutang - v_row.jumlah) WHERE id = v_row.kedai_id;
          v_baki := v_row.jumlah;
          FOR t IN SELECT id, jumlah FROM transaksi WHERE kedai_id = v_row.kedai_id AND status = 'hutang' ORDER BY tarikh_masa ASC LOOP
            EXIT WHEN v_baki < t.jumlah;
            UPDATE transaksi SET status = 'selesai' WHERE id = t.id;
            v_baki := v_baki - t.jumlah;
          END LOOP;
        END IF;
      ELSE
        IF v_row.settlement_penuh THEN
          UPDATE transaksi SET status = 'selesai' WHERE kedai_id IS NULL AND nama_pembeli = v_row.nama_pembeli AND status = 'hutang';
        ELSE
          v_baki := v_row.jumlah;
          FOR t IN SELECT id, jumlah FROM transaksi WHERE kedai_id IS NULL AND nama_pembeli = v_row.nama_pembeli AND status = 'hutang' ORDER BY tarikh_masa ASC LOOP
            EXIT WHEN v_baki < t.jumlah;
            UPDATE transaksi SET status = 'selesai' WHERE id = t.id;
            v_baki := v_baki - t.jumlah;
          END LOOP;
        END IF;
      END IF;
    END IF;

    UPDATE permohonan_bayaran_hutang SET status = p_status, disahkan_oleh = v_admin_user_id, disahkan_pada = now() WHERE id = p_id;
    RETURN 'Bayaran hutang RM' || v_row.jumlah || ' ' || CASE WHEN p_status='disahkan' THEN 'disahkan ✅' ELSE 'ditolak ✕' END;

  ELSIF p_jadual = 'serahan_produk' THEN
    SELECT * INTO v_row FROM serahan_produk WHERE id = p_id AND status = 'menunggu';
    IF NOT FOUND THEN RAISE EXCEPTION 'Rekod tidak dijumpai atau sudah diputuskan'; END IF;

    IF v_row.jenis = 'ambil' THEN
      IF p_status = 'disahkan' THEN
        UPDATE stok SET stok = stok - v_row.kuantiti WHERE id = v_row.stok_id AND stok >= v_row.kuantiti;
        IF NOT FOUND THEN RAISE EXCEPTION 'Stok gudang tidak mencukupi lagi — mungkin sudah diambil/pindah sejak permohonan dihantar'; END IF;
        INSERT INTO stok_pekerja (pekerja_id, stok_id, kuantiti) VALUES (v_row.pekerja_id, v_row.stok_id, v_row.kuantiti)
          ON CONFLICT (pekerja_id, stok_id) DO UPDATE SET kuantiti = stok_pekerja.kuantiti + v_row.kuantiti;
      END IF;
    ELSIF v_row.jenis IN ('reject','baik') THEN
      IF p_status = 'ditolak' THEN
        INSERT INTO stok_pekerja (pekerja_id, stok_id, kuantiti) VALUES (v_row.pekerja_id, v_row.stok_id, v_row.kuantiti)
          ON CONFLICT (pekerja_id, stok_id) DO UPDATE SET kuantiti = stok_pekerja.kuantiti + v_row.kuantiti;
      ELSIF p_status = 'disahkan' AND v_row.jenis = 'baik' THEN
        UPDATE stok SET stok = stok + v_row.kuantiti WHERE id = v_row.stok_id;
      END IF;
    ELSE
      RAISE EXCEPTION 'Jenis serahan_produk tidak disokong via Telegram: %', v_row.jenis;
    END IF;

    UPDATE serahan_produk SET status = p_status, disahkan_oleh = v_admin_user_id, disahkan_pada = now() WHERE id = p_id;
    RETURN 'Serahan produk (' || v_row.stok_nama || ' ×' || v_row.kuantiti || ') ' || CASE WHEN p_status='disahkan' THEN 'disahkan ✅' ELSE 'ditolak ✕' END;

  ELSIF p_jadual = 'baucar_bayaran' THEN
    IF p_status = 'disahkan' THEN
      UPDATE baucar_bayaran SET status = 'diluluskan', diluluskan_oleh = v_admin_user_id, diluluskan_pada = now()
        WHERE id = p_id AND status = 'draf';
      IF NOT FOUND THEN RAISE EXCEPTION 'Baucar tidak dijumpai atau bukan lagi draf (mungkin sudah diluluskan/dibayar/dibatalkan)'; END IF;
      RETURN 'Baucar harian diluluskan ✅';
    ELSE
      UPDATE baucar_bayaran SET status = 'dibatalkan' WHERE id = p_id AND status = 'draf';
      IF NOT FOUND THEN RAISE EXCEPTION 'Baucar tidak dijumpai atau bukan lagi draf (mungkin sudah diluluskan/dibayar/dibatalkan)'; END IF;
      RETURN 'Baucar harian dibatalkan ✕';
    END IF;

  ELSE
    RAISE EXCEPTION 'Jadual tidak disokong via Telegram: %', p_jadual;
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.telegram_putuskan(bigint,text,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.telegram_putuskan(bigint,text,text,text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.telegram_putuskan(bigint,text,text,text) TO service_role;
