-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 190: Pekerja minta PINDAH STOK bawaan ke pekerja lain — PENERIMA sahkan,
-- pemakluman ke kumpulan WhatsApp Team Sales.
-- STATUS: DRAF — BELUM DIJALANKAN. Jalankan hanya selepas Amirul lulus.
-- Bergantung pada SQL 176 (SUDAH dijalankan): lajur pasangan_id/dilakukan_oleh,
-- private.batalkan_pindahan, terima_pindahan_stok, tolak_pindahan_stok, auto-batal 3 hari.
--
-- Aliran:
--  1. Pekerja (pengirim) hantar minta_pindah_stok: stok DITAHAN dari beg pengirim serta-merta,
--     log 'pindah_keluar' = disahkan, log 'pindah_masuk' = MENUNGGU (sama seperti SQL 176).
--     Stok penerima BELUM bertambah.
--  2. PENERIMA tekan Terima (stok masuk bawaan) atau Tolak (stok pulang ke pengirim) — fungsi
--     terima_pindahan_stok / tolak_pindahan_stok sedia ada. Tiada kelulusan pemilik.
--  3. Pengirim boleh batal selagi menunggu (batal_pindahan_pengirim). Pemilik boleh batal
--     (batal_pindahan_stok, SQL 176). Auto-batal 3 hari (SQL 176).
--  4. Setiap permohonan baharu DAN setiap keputusan (diterima/ditolak/dibatal) dihantar ke
--     kumpulan WhatsApp Team Sales melalui private.pemakluman_kelulusan (skrip VPS sedia ada,
--     cron setiap minit). Ini juga meliputi pindahan yang dimulakan pemilik (SQL 176).
-- Tiada jenis baharu, tiada perubahan pada telegram_putuskan / edge function.
-- ═══════════════════════════════════════════════════════════

-- ── A. Pekerja hantar permohonan ──
CREATE OR REPLACE FUNCTION public.minta_pindah_stok(p_id text, p_kepada uuid, p_stok_id text, p_qty int)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_nama text; v_masuk_id text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Log masuk diperlukan'; END IF;
  IF is_pemilik() THEN RAISE EXCEPTION 'Pemilik guna butang Pindah Stok terus'; END IF;
  IF p_qty IS NULL OR p_qty <= 0 THEN RAISE EXCEPTION 'Kuantiti mesti lebih 0'; END IF;
  IF p_kepada = auth.uid() THEN RAISE EXCEPTION 'Tidak boleh pindah kepada diri sendiri'; END IF;
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = p_kepada AND role = 'pekerja' AND status = 'aktif') THEN
    RAISE EXCEPTION 'Penerima mesti pekerja aktif';
  END IF;
  SELECT nama INTO v_nama FROM stok WHERE id = p_stok_id;
  IF v_nama IS NULL THEN RAISE EXCEPTION 'Produk tidak dijumpai'; END IF;

  -- Tahan stok daripada pengirim (tidak boleh dijual dua kali)
  UPDATE stok_pekerja SET kuantiti = kuantiti - p_qty
    WHERE pekerja_id = auth.uid() AND stok_id = p_stok_id AND kuantiti >= p_qty;
  IF NOT FOUND THEN RAISE EXCEPTION 'Stok bawaan anda tidak mencukupi'; END IF;

  v_masuk_id := gen_random_uuid()::text;
  INSERT INTO serahan_produk (id, pekerja_id, rujuk_pekerja_id, stok_id, stok_nama, kuantiti, jenis, status, dilakukan_oleh)
  VALUES (p_id, auth.uid(), p_kepada, p_stok_id, v_nama, p_qty, 'pindah_keluar', 'disahkan', auth.uid());
  INSERT INTO serahan_produk (id, pekerja_id, rujuk_pekerja_id, stok_id, stok_nama, kuantiti, jenis, status, pasangan_id, dilakukan_oleh)
  VALUES (v_masuk_id, p_kepada, auth.uid(), p_stok_id, v_nama, p_qty, 'pindah_masuk', 'menunggu', p_id, auth.uid());
END;
$$;
REVOKE EXECUTE ON FUNCTION public.minta_pindah_stok(text, uuid, text, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.minta_pindah_stok(text, uuid, text, int) TO authenticated;

-- ── B. Pengirim batal pindahan yang masih menunggu (stok pulang kepadanya) ──
CREATE OR REPLACE FUNCTION public.batal_pindahan_pengirim(p_id text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_sumber uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Log masuk diperlukan'; END IF;
  SELECT rujuk_pekerja_id INTO v_sumber FROM serahan_produk
    WHERE id = p_id AND jenis = 'pindah_masuk' AND status = 'menunggu';
  IF NOT FOUND THEN RAISE EXCEPTION 'Pindahan tidak dijumpai atau sudah diputuskan'; END IF;
  IF v_sumber <> auth.uid() THEN RAISE EXCEPTION 'Hanya pengirim boleh membatalkan pindahan ini'; END IF;
  PERFORM private.batalkan_pindahan(p_id, 'dibatal_pengirim');
END;
$$;
REVOKE EXECUTE ON FUNCTION public.batal_pindahan_pengirim(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.batal_pindahan_pengirim(text) TO authenticated;

-- ── C. Pemakluman kumpulan WhatsApp Team Sales ──
CREATE OR REPLACE FUNCTION private.pemakluman_pindah_stok() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'private', 'pg_temp' AS $$
DECLARE v_dari text; v_kepada text; v_masa text; v_teks text; v_hasil text;
BEGIN
  -- pindah_masuk: pekerja_id = penerima, rujuk_pekerja_id = pengirim
  SELECT nama INTO v_kepada FROM profiles WHERE id = NEW.pekerja_id;
  SELECT nama INTO v_dari FROM profiles WHERE id = NEW.rujuk_pekerja_id;
  v_masa := to_char(now() AT TIME ZONE 'Asia/Kuala_Lumpur', 'DD/MM/YY, FMHH12:MI')
    || CASE WHEN extract(hour FROM (now() AT TIME ZONE 'Asia/Kuala_Lumpur')) < 12 THEN ' PG' ELSE ' PTG' END;

  IF TG_OP = 'INSERT' THEN
    v_hasil := '⏳ Menunggu ' || COALESCE(v_kepada, '?') || ' sahkan terima';
  ELSIF NEW.status = 'disahkan' THEN
    v_hasil := 'Diterima ' || COALESCE(v_kepada, '?') || ' ✅';
  ELSE
    v_hasil := CASE NEW.sebab
      WHEN 'ditolak_penerima' THEN 'Ditolak ' || COALESCE(v_kepada, '?') || ' ✕ (stok pulang kepada ' || COALESCE(v_dari, '?') || ')'
      WHEN 'dibatal_pengirim'  THEN 'Dibatalkan pengirim ✕ (stok pulang kepada ' || COALESCE(v_dari, '?') || ')'
      WHEN 'dibatal_pemilik'   THEN 'Dibatalkan pemilik ✕ (stok pulang kepada ' || COALESCE(v_dari, '?') || ')'
      WHEN 'dibatal_auto'      THEN 'Dibatalkan automatik (3 hari tiada jawapan) ✕ (stok pulang kepada ' || COALESCE(v_dari, '?') || ')'
      ELSE 'Dibatalkan ✕ (stok pulang kepada ' || COALESCE(v_dari, '?') || ')' END;
  END IF;

  v_teks := '📢 *PINDAH STOK — WAFI TIJARAH TRADING*' || E'\n\n'
    || '🔀 ' || COALESCE(v_dari, '?') || ' → ' || COALESCE(v_kepada, '?') || E'\n'
    || COALESCE(NEW.stok_nama, '?') || ' ×' || NEW.kuantiti
    || E'\n\n➡️ ' || v_hasil || ' · ' || v_masa;

  INSERT INTO private.pemakluman_kelulusan (jadual, rekod_id, status, teks)
  VALUES ('serahan_produk', NEW.id::text, CASE WHEN NEW.status = 'ditolak' THEN 'ditolak' ELSE 'disahkan' END, v_teks);
  RETURN NEW;
EXCEPTION WHEN others THEN
  RAISE WARNING '[pemakluman_pindah_stok] gagal utk %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$;
REVOKE EXECUTE ON FUNCTION private.pemakluman_pindah_stok() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_pemakluman_pindah_baru ON public.serahan_produk;
CREATE TRIGGER trg_pemakluman_pindah_baru AFTER INSERT ON public.serahan_produk
  FOR EACH ROW WHEN (NEW.jenis = 'pindah_masuk' AND NEW.status = 'menunggu')
  EXECUTE FUNCTION private.pemakluman_pindah_stok();

DROP TRIGGER IF EXISTS trg_pemakluman_pindah_putus ON public.serahan_produk;
CREATE TRIGGER trg_pemakluman_pindah_putus AFTER UPDATE OF status ON public.serahan_produk
  FOR EACH ROW WHEN (NEW.jenis = 'pindah_masuk' AND OLD.status = 'menunggu' AND NEW.status IN ('disahkan','ditolak'))
  EXECUTE FUNCTION private.pemakluman_pindah_stok();

-- ── Semak selepas laksana (SELECT sahaja) ──
-- SELECT tgname FROM pg_trigger WHERE tgrelid='public.serahan_produk'::regclass AND NOT tgisinternal;
-- SELECT proname FROM pg_proc WHERE proname IN ('minta_pindah_stok','batal_pindahan_pengirim','pemakluman_pindah_stok');
