-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 146: Integrasi Telegram — notifikasi pemilik +
-- arahan/kelulusan terus dari Telegram (pemilik tak sempat buka
-- sistem bila ada permintaan pekerja).
--
-- Reka bentuk keselamatan (PENTING, baca sebelum ubah):
--  • telegram_admin memaut SATU chat_id Telegram kpd SATU akaun
--    pemilik (user_id). Pautan berlaku via kod sekali-guna 6-aksara
--    (telegram_link_codes, tamat 15 minit) — dijana oleh pemilik
--    sendiri dlm Sistem Pengurusan (RPC jana_kod_pautan_telegram),
--    disahkan oleh Edge Function telegram-webhook bila pemilik hantar
--    "/link KOD" ke bot.
--  • telegram_putuskan() ialah SATU-SATUNYA cara tindakan tulis
--    (lulus/tolak) boleh berlaku dari Telegram. Ia SECURITY DEFINER,
--    mengesahkan chat_id berdaftar & masih aktif & terikat kpd akaun
--    role='pemilik' SEBELUM buat apa-apa perubahan — EXECUTE
--    fungsi ni DIHADKAN kpd service_role sahaja (REVOKE drpd PUBLIC/
--    anon/authenticated di bawah), supaya HANYA Edge Function
--    telegram-webhook (yg pegang SUPABASE_SERVICE_ROLE_KEY sbg
--    secret) boleh panggilnya — bukan sesiapa dari klien/browser.
--  • Logik settle hutang (kedai/peribadi, penuh/sebahagian) DISALIN
--    terus ke dalam telegram_putuskan() (bukan panggil rekod_bayaran()
--    dll sedia ada) sebab fungsi2 asal tu semak auth.uid() sendiri
--    (akan gagal bila dipanggil drpd sesi service_role yg tiada
--    auth.uid()). Salinan ni kekal SAMA logik dgn rekod_bayaran/
--    rekod_bayaran_penuh/rekod_bayaran_peribadi/rekod_bayaran_penuh_peribadi
--    — jangan ubah salah satu tanpa ubah yg lain jika logik settle
--    hutang berubah kelak.
--  • permohonan_padam (padam rekod) SENGAJA TIDAK didedahkan sbg
--    tindakan Telegram — jenis 'transaksi' perlukan kiraan minyak
--    pulih (JS kiraMinyakPulihTransaksi, bukan mudah disalin ke SQL)
--    & tindakan padam KEKAL/tak boleh diundur. /padam di Telegram
--    cuma SENARAI (baca sahaja) — arah pemilik buka Sistem Pengurusan
--    utk padam sebenar.
-- ═══════════════════════════════════════════════════════════

-- ── Jadual: pendaftaran admin Telegram ──────────────────────
CREATE TABLE IF NOT EXISTS public.telegram_admin (
  chat_id bigint PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  nama text,
  linked_at timestamptz NOT NULL DEFAULT now(),
  aktif boolean NOT NULL DEFAULT true,
  notifikasi_aktif boolean NOT NULL DEFAULT true
);
ALTER TABLE public.telegram_admin ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "pemilik lihat semua admin telegram" ON public.telegram_admin;
CREATE POLICY "pemilik lihat semua admin telegram" ON public.telegram_admin
  FOR SELECT USING (is_pemilik());

DROP POLICY IF EXISTS "pemilik urus admin telegram" ON public.telegram_admin;
CREATE POLICY "pemilik urus admin telegram" ON public.telegram_admin
  FOR UPDATE USING (is_pemilik()) WITH CHECK (is_pemilik());

DROP POLICY IF EXISTS "pemilik padam admin telegram" ON public.telegram_admin;
CREATE POLICY "pemilik padam admin telegram" ON public.telegram_admin
  FOR DELETE USING (is_pemilik());
-- Tiada polisi INSERT client — pendaftaran chat_id baharu HANYA via
-- Edge Function telegram-webhook (service_role, bypass RLS) bila kod
-- pautan sah dihantar.

-- ── Jadual: kod pautan sekali-guna ───────────────────────────
CREATE TABLE IF NOT EXISTS public.telegram_link_codes (
  code text PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  used boolean NOT NULL DEFAULT false
);
ALTER TABLE public.telegram_link_codes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "pemilik lihat kod sendiri" ON public.telegram_link_codes;
CREATE POLICY "pemilik lihat kod sendiri" ON public.telegram_link_codes
  FOR SELECT USING (user_id = auth.uid());

-- ── Ambang stok rendah (boleh laras kelak, lalai 10 unit) ────
ALTER TABLE public.tetapan ADD COLUMN IF NOT EXISTS stok_ambang_minimum integer NOT NULL DEFAULT 10;

-- ── RPC: pemilik jana kod pautan Telegram (15 minit) ─────────
CREATE OR REPLACE FUNCTION public.jana_kod_pautan_telegram()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_kod text;
BEGIN
  IF NOT is_pemilik() THEN
    RAISE EXCEPTION 'Hanya pemilik boleh jana kod pautan Telegram';
  END IF;
  DELETE FROM telegram_link_codes WHERE user_id = auth.uid() AND used = false;
  v_kod := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
  INSERT INTO telegram_link_codes (code, user_id, expires_at) VALUES (v_kod, auth.uid(), now() + interval '15 minutes');
  RETURN v_kod;
END;
$function$;

-- ── RPC: dispatcher lulus/tolak DARI TELEGRAM sahaja ─────────
-- p_jadual: 'serahan_cash' | 'permohonan_cuti' | 'permohonan_bayaran_hutang' | 'serahan_produk'
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

  ELSE
    RAISE EXCEPTION 'Jadual tidak disokong via Telegram: %', p_jadual;
  END IF;
END;
$function$;

-- KUNCI KESELAMATAN: hanya service_role (Edge Function telegram-webhook)
-- boleh panggil telegram_putuskan() — TIADA client (anon/authenticated)
-- boleh capai terus dari browser/app.
REVOKE ALL ON FUNCTION public.telegram_putuskan(bigint,text,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.telegram_putuskan(bigint,text,text,text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.telegram_putuskan(bigint,text,text,text) TO service_role;

-- ── Kemaskini trigger sedia ada: sertakan record_id/jenis_rekod ──
-- supaya Edge Function boleh papar butang "✅ Lulus / ✕ Tolak" pada
-- mesej Telegram yg merujuk terus kepada rekod tsb. Guna semula SATU
-- fungsi generik notify_pemilik_kelulusan() (SQL_TAMBAHAN_65) yg dah
-- sedia dipasang pada 5 jadual (serahan_produk, permohonan_bayaran_hutang,
-- permohonan_padam, permohonan_cuti, serahan_cash) — hanya body fungsi
-- diubah, trigger sedia ada TAK perlu dicipta semula.
CREATE OR REPLACE FUNCTION public.notify_pemilik_kelulusan()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_pekerja_nama text;
  v_jenis text;
  v_butiran text;
  v_jenis_rekod text;
BEGIN
  IF TG_TABLE_NAME = 'serahan_produk' THEN
    IF NEW.status <> 'menunggu' THEN
      RETURN NEW;
    END IF;
    IF NEW.jenis = 'ambil' AND NEW.sebab IS NOT NULL THEN
      RETURN NEW;
    END IF;
  END IF;

  IF TG_TABLE_NAME = 'permohonan_bayaran_hutang' AND NEW.status <> 'menunggu' THEN
    RETURN NEW;
  END IF;

  SELECT nama INTO v_pekerja_nama FROM profiles WHERE id = NEW.pekerja_id;

  IF TG_TABLE_NAME = 'permohonan_padam' THEN
    v_jenis := 'Permohonan Padam';
    v_butiran := COALESCE(NEW.rekod_label, NEW.jenis) || COALESCE(' — Sebab: ' || NEW.sebab, '');
    v_jenis_rekod := 'permohonan_padam'; -- tiada butang Telegram (baca sahaja, lihat nota SQL_TAMBAHAN_146)
  ELSIF TG_TABLE_NAME = 'permohonan_cuti' THEN
    v_jenis := 'Permohonan Cuti/MC/Off';
    v_butiran := NEW.jenis || ' (' || to_char(NEW.tarikh_mula,'DD/MM/YYYY') || ' - ' || to_char(NEW.tarikh_tamat,'DD/MM/YYYY') || ')';
    v_jenis_rekod := 'permohonan_cuti';
  ELSIF TG_TABLE_NAME = 'serahan_cash' THEN
    v_jenis := 'Serahan Duit Cash';
    v_butiran := 'RM' || NEW.jumlah;
    v_jenis_rekod := 'serahan_cash';
  ELSIF TG_TABLE_NAME = 'serahan_produk' THEN
    v_jenis := CASE WHEN NEW.jenis = 'ambil' THEN 'Permohonan Ambil Stok' ELSE 'Serahan Produk Reject' END;
    v_butiran := NEW.stok_nama || ' ×' || NEW.kuantiti;
    v_jenis_rekod := 'serahan_produk';
  ELSIF TG_TABLE_NAME = 'permohonan_bayaran_hutang' THEN
    v_jenis := 'Permohonan Bayaran Hutang';
    v_butiran := 'RM' || NEW.jumlah || ' (' || NEW.kaedah_bayaran || ')';
    v_jenis_rekod := 'permohonan_bayaran_hutang';
  ELSE
    RETURN NEW;
  END IF;

  PERFORM net.http_post(
    url := 'https://smepriytkoxkmpvjvvzq.supabase.co/functions/v1/notifikasi-kelulusan-pemilik',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNtZXByaXl0a294a21wdmp2dnpxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMzODE1OTcsImV4cCI6MjA5ODk1NzU5N30.bLDjFNZ_gMm9ufCkA4TeFbw1rysuLnlQN-qW_WW0zr8'
    ),
    body := jsonb_build_object(
      'jenis', v_jenis, 'pekerja_nama', COALESCE(v_pekerja_nama, '?'), 'butiran', v_butiran,
      'record_id', NEW.id, 'jenis_rekod', v_jenis_rekod
    )
  );
  RETURN NEW;
END;
$function$;
