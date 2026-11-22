-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 190: Pekerja minta PINDAH STOK bawaan ke pekerja lain — pemilik lulus (web + Telegram).
-- STATUS: DRAF — BELUM DIJALANKAN. Jalankan hanya selepas Amirul lulus.
--
-- Aliran:
--  1. Pekerja hantar permohonan (minta_pindah_stok): satu baris serahan_produk jenis
--     'pindah_minta', status 'menunggu'. pekerja_id = pengirim, rujuk_pekerja_id = penerima.
--     TIADA stok bergerak lagi. Telegram pemilik terima kad Lulus/Tolak (corak sama 'ambil').
--  2. Pemilik lulus di web (putuskan_pindah_minta) ATAU Telegram (telegram_putuskan, jadual
--     serahan_produk): stok_pekerja pengirim ditolak, penerima ditambah, dan 2 baris log
--     pindah_keluar + pindah_masuk (disahkan) dicipta supaya semua pengiraan baki/sejarah
--     sedia ada kekal betul. Tolak = tiada apa berubah.
--  3. Penerima TIDAK perlu sahkan (pemilik sahaja yang lulus).
--  Baris 'pindah_minta' tidak dikira dalam baki (tiada dalam SIGN) — hanya permohonan.
--  Pindahan pemilik terus (SQL 176) tidak diubah.
-- ═══════════════════════════════════════════════════════════

-- ── A. Benarkan jenis baharu ──
ALTER TABLE public.serahan_produk DROP CONSTRAINT serahan_produk_jenis_check;
ALTER TABLE public.serahan_produk ADD CONSTRAINT serahan_produk_jenis_check
  CHECK (jenis = ANY (ARRAY['baik','reject','ambil','pindah_keluar','pindah_masuk','restock','padam_pulang','pindah_minta']));

-- ── B. Pekerja hantar permohonan ──
CREATE OR REPLACE FUNCTION public.minta_pindah_stok(p_id text, p_kepada uuid, p_stok_id text, p_qty int)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_nama text; v_bawaan int; v_menunggu int;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Log masuk diperlukan'; END IF;
  IF is_pemilik() THEN RAISE EXCEPTION 'Pemilik guna butang Pindah Stok terus (tidak perlu permohonan)'; END IF;
  IF p_qty IS NULL OR p_qty <= 0 THEN RAISE EXCEPTION 'Kuantiti mesti lebih 0'; END IF;
  IF p_kepada = auth.uid() THEN RAISE EXCEPTION 'Tidak boleh pindah kepada diri sendiri'; END IF;
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = p_kepada AND role = 'pekerja' AND status = 'aktif') THEN
    RAISE EXCEPTION 'Penerima mesti pekerja aktif';
  END IF;
  SELECT nama INTO v_nama FROM stok WHERE id = p_stok_id;
  IF v_nama IS NULL THEN RAISE EXCEPTION 'Produk tidak dijumpai'; END IF;

  SELECT COALESCE(SUM(kuantiti), 0) INTO v_bawaan FROM stok_pekerja WHERE pekerja_id = auth.uid() AND stok_id = p_stok_id;
  SELECT COALESCE(SUM(kuantiti), 0) INTO v_menunggu FROM serahan_produk
    WHERE pekerja_id = auth.uid() AND stok_id = p_stok_id AND jenis = 'pindah_minta' AND status = 'menunggu';
  IF v_bawaan - v_menunggu < p_qty THEN
    RAISE EXCEPTION 'Stok bawaan tidak mencukupi (bawaan %, sudah dipohon pindah %)', v_bawaan, v_menunggu;
  END IF;

  INSERT INTO serahan_produk (id, pekerja_id, rujuk_pekerja_id, stok_id, stok_nama, kuantiti, jenis, status, dilakukan_oleh)
  VALUES (p_id, auth.uid(), p_kepada, p_stok_id, v_nama, p_qty, 'pindah_minta', 'menunggu', auth.uid());
END;
$$;
REVOKE EXECUTE ON FUNCTION public.minta_pindah_stok(text, uuid, text, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.minta_pindah_stok(text, uuid, text, int) TO authenticated;

-- ── C. Pelaksana dalaman (dikongsi web + Telegram) ──
CREATE OR REPLACE FUNCTION private.putuskan_pindah_minta(p_id text, p_status text, p_oleh uuid) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v serahan_produk%ROWTYPE; v_keluar text; v_masuk text; v_dari text; v_kepada text;
BEGIN
  IF p_status NOT IN ('disahkan','ditolak') THEN RAISE EXCEPTION 'Status tidak sah'; END IF;
  SELECT * INTO v FROM serahan_produk WHERE id = p_id AND jenis = 'pindah_minta' AND status = 'menunggu' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Permohonan tidak dijumpai atau sudah diputuskan'; END IF;
  SELECT nama INTO v_dari FROM profiles WHERE id = v.pekerja_id;
  SELECT nama INTO v_kepada FROM profiles WHERE id = v.rujuk_pekerja_id;

  IF p_status = 'disahkan' THEN
    UPDATE stok_pekerja SET kuantiti = kuantiti - v.kuantiti
      WHERE pekerja_id = v.pekerja_id AND stok_id = v.stok_id AND kuantiti >= v.kuantiti;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Stok bawaan % tidak mencukupi lagi (mungkin sudah dijual/dipulang sejak permohonan)', COALESCE(v_dari, 'pekerja');
    END IF;
    INSERT INTO stok_pekerja (pekerja_id, stok_id, kuantiti) VALUES (v.rujuk_pekerja_id, v.stok_id, v.kuantiti)
      ON CONFLICT (pekerja_id, stok_id) DO UPDATE SET kuantiti = stok_pekerja.kuantiti + v.kuantiti;

    v_keluar := gen_random_uuid()::text; v_masuk := gen_random_uuid()::text;
    INSERT INTO serahan_produk (id, pekerja_id, rujuk_pekerja_id, stok_id, stok_nama, kuantiti, jenis, status, dilakukan_oleh, disahkan_oleh, disahkan_pada)
    VALUES (v_keluar, v.pekerja_id, v.rujuk_pekerja_id, v.stok_id, v.stok_nama, v.kuantiti, 'pindah_keluar', 'disahkan', v.pekerja_id, p_oleh, now());
    INSERT INTO serahan_produk (id, pekerja_id, rujuk_pekerja_id, stok_id, stok_nama, kuantiti, jenis, status, pasangan_id, dilakukan_oleh, disahkan_oleh, disahkan_pada)
    VALUES (v_masuk, v.rujuk_pekerja_id, v.pekerja_id, v.stok_id, v.stok_nama, v.kuantiti, 'pindah_masuk', 'disahkan', v_keluar, v.pekerja_id, p_oleh, now());
  END IF;

  UPDATE serahan_produk SET status = p_status, disahkan_oleh = p_oleh, disahkan_pada = now() WHERE id = p_id;
  RETURN 'Pindah stok ' || v.stok_nama || ' ×' || v.kuantiti || ' (' || COALESCE(v_dari,'?') || ' → ' || COALESCE(v_kepada,'?') || ') '
    || CASE WHEN p_status = 'disahkan' THEN 'diluluskan ✅' ELSE 'ditolak ✕' END;
END;
$$;
REVOKE EXECUTE ON FUNCTION private.putuskan_pindah_minta(text, text, uuid) FROM PUBLIC, anon, authenticated;

-- ── D. Pemilik lulus/tolak di web ──
CREATE OR REPLACE FUNCTION public.putuskan_pindah_minta(p_id text, p_status text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Log masuk diperlukan'; END IF;
  IF NOT is_pemilik() THEN RAISE EXCEPTION 'Hanya pemilik boleh luluskan permohonan pindah stok'; END IF;
  PERFORM private.putuskan_pindah_minta(p_id, p_status, auth.uid());
END;
$$;
REVOKE EXECUTE ON FUNCTION public.putuskan_pindah_minta(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.putuskan_pindah_minta(text, text) TO authenticated;

-- ── E. Telegram: cabang baharu dalam telegram_putuskan (jadual serahan_produk, jenis pindah_minta) ──
-- Selebihnya SAMA seperti definisi live (disalin 22 Nov 2026).
CREATE OR REPLACE FUNCTION public.telegram_putuskan(p_admin_chat_id bigint, p_jadual text, p_id text, p_status text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_admin_user_id uuid;
  v_ok boolean;
  v_row RECORD;
  v_kod text;
  v_kod_cuba text;
  v_n int;
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
          UPDATE transaksi SET status = 'selesai', jumlah_dibayar = GREATEST(jumlah_dibayar, jumlah)
            WHERE kedai_id = v_row.kedai_id AND status = 'hutang';
        ELSE
          PERFORM agih_bayaran_hutang(v_row.kedai_id, NULL, v_row.jumlah, v_row.tarikh_diterima);
        END IF;
      ELSE
        IF v_row.settlement_penuh THEN
          UPDATE transaksi SET status = 'selesai', jumlah_dibayar = GREATEST(jumlah_dibayar, jumlah)
            WHERE kedai_id IS NULL AND nama_pembeli = v_row.nama_pembeli AND status = 'hutang';
        ELSE
          PERFORM agih_bayaran_hutang(NULL, v_row.nama_pembeli, v_row.jumlah);
        END IF;
      END IF;
    END IF;

    UPDATE permohonan_bayaran_hutang SET status = p_status, disahkan_oleh = v_admin_user_id, disahkan_pada = now() WHERE id = p_id;
    RETURN 'Bayaran hutang RM' || v_row.jumlah || ' ' || CASE WHEN p_status='disahkan' THEN 'disahkan ✅' ELSE 'ditolak ✕' END;

  ELSIF p_jadual = 'serahan_produk' THEN
    SELECT * INTO v_row FROM serahan_produk WHERE id = p_id AND status = 'menunggu';
    IF NOT FOUND THEN RAISE EXCEPTION 'Rekod tidak dijumpai atau sudah diputuskan'; END IF;

    IF v_row.jenis = 'pindah_minta' THEN
      RETURN private.putuskan_pindah_minta(p_id, p_status, v_admin_user_id);
    ELSIF v_row.jenis = 'ambil' THEN
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

  ELSIF p_jadual = 'affiliates' THEN
    SELECT * INTO v_row FROM affiliates WHERE id = p_id::uuid AND status = 'menunggu';
    IF NOT FOUND THEN RAISE EXCEPTION 'Permohonan tidak dijumpai atau sudah diproses'; END IF;

    IF p_status = 'disahkan' THEN
      v_kod := upper(regexp_replace(split_part(v_row.nama, ' ', 1), '[^A-Za-z]', '', 'g'));
      IF v_kod = '' THEN v_kod := 'AFF'; END IF;
      v_kod_cuba := v_kod;
      v_n := 1;
      WHILE EXISTS (SELECT 1 FROM affiliates WHERE kod_affiliate = v_kod_cuba) LOOP
        v_n := v_n + 1;
        v_kod_cuba := v_kod || v_n;
      END LOOP;
      UPDATE affiliates SET
        kod_affiliate = v_kod_cuba, status = 'aktif',
        disahkan_oleh = v_admin_user_id, disahkan_pada = now()
      WHERE id = p_id::uuid AND status = 'menunggu';
      IF NOT FOUND THEN RAISE EXCEPTION 'Permohonan tidak dijumpai atau sudah diproses'; END IF;
      RETURN 'Affiliate diluluskan ✅ Kod: ' || v_kod_cuba || ' (komisen ' || v_row.kadar_komisen_peratus || '%, diskaun ' || v_row.kadar_diskaun_peratus || '%)';
    ELSE
      UPDATE affiliates SET status = 'ditolak', disahkan_oleh = v_admin_user_id, disahkan_pada = now()
      WHERE id = p_id::uuid AND status = 'menunggu';
      IF NOT FOUND THEN RAISE EXCEPTION 'Permohonan tidak dijumpai atau sudah diproses'; END IF;
      RETURN 'Permohonan affiliate dibatalkan ✕';
    END IF;

  ELSE
    RAISE EXCEPTION 'Jadual tidak disokong via Telegram: %', p_jadual;
  END IF;
END;
$$;

-- ── F. Notifikasi Telegram pemilik untuk permohonan baharu ──
-- Fungsi notify_pemilik_kelulusan() generik TIDAK diubah; 'pindah_minta' dikecualikan daripadanya
-- dan diberi pencetus sendiri (butiran memaparkan nama penerima). Kad Lulus/Tolak guna
-- jenis_rekod 'serahan_produk' => butang sp: sedia ada dalam edge function (tiada deploy edge fn diperlukan).
CREATE OR REPLACE FUNCTION public.notify_pindah_minta() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_dari text; v_kepada text;
BEGIN
  IF NEW.status <> 'menunggu' THEN RETURN NEW; END IF;
  SELECT nama INTO v_dari FROM profiles WHERE id = NEW.pekerja_id;
  SELECT nama INTO v_kepada FROM profiles WHERE id = NEW.rujuk_pekerja_id;
  PERFORM net.http_post(
    url := 'https://smepriytkoxkmpvjvvzq.supabase.co/functions/v1/notifikasi-kelulusan-pemilik',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNtZXByaXl0a294a21wdmp2dnpxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMzODE1OTcsImV4cCI6MjA5ODk1NzU5N30.bLDjFNZ_gMm9ufCkA4TeFbw1rysuLnlQN-qW_WW0zr8'),
    body := jsonb_build_object(
      'jenis', 'Permohonan Pindah Stok', 'pekerja_nama', COALESCE(v_dari, '?'),
      'butiran', NEW.stok_nama || ' ×' || NEW.kuantiti || E'\n🔀 Kepada: ' || COALESCE(v_kepada, '?'),
      'record_id', NEW.id, 'jenis_rekod', 'serahan_produk')
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_pemilik_produk ON public.serahan_produk;
CREATE TRIGGER trg_notify_pemilik_produk AFTER INSERT ON public.serahan_produk
  FOR EACH ROW WHEN (NEW.jenis NOT IN ('pindah_keluar','pindah_masuk','pindah_minta'))
  EXECUTE FUNCTION notify_pemilik_kelulusan();

DROP TRIGGER IF EXISTS trg_notify_pindah_minta ON public.serahan_produk;
CREATE TRIGGER trg_notify_pindah_minta AFTER INSERT ON public.serahan_produk
  FOR EACH ROW WHEN (NEW.jenis = 'pindah_minta')
  EXECUTE FUNCTION notify_pindah_minta();

-- Tiada pengumuman WhatsApp Team Sales untuk pindah stok (pemakluman_keputusan dikecualikan).
DROP TRIGGER IF EXISTS trg_pemakluman_keputusan ON public.serahan_produk;
CREATE TRIGGER trg_pemakluman_keputusan AFTER UPDATE OF status ON public.serahan_produk
  FOR EACH ROW WHEN (OLD.status IS DISTINCT FROM NEW.status
                     AND NEW.jenis NOT IN ('pindah_keluar','pindah_masuk','pindah_minta'))
  EXECUTE FUNCTION pemakluman_keputusan();

-- ── Semak selepas laksana (SELECT sahaja) ──
-- SELECT tgname FROM pg_trigger WHERE tgrelid='public.serahan_produk'::regclass AND NOT tgisinternal;
-- SELECT proname FROM pg_proc WHERE proname IN ('minta_pindah_stok','putuskan_pindah_minta','notify_pindah_minta');
