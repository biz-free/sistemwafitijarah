-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 153: SEMUA keputusan kelulusan pemilik yang melibatkan pekerja
-- diumumkan ke kumpulan WhatsApp Team Sales — tidak kira dibuat melalui
-- Telegram ATAU Sistem Pengurusan (web).
--
-- Sebelum ini (SQL 150/151) hanya keputusan melalui butang Telegram direkod ke
-- private.pemakluman_kelulusan. Keputusan di web (putuskan_bayaran_hutang,
-- putuskan_serahan_produk, putuskan_ambil_stok, kemas kini terus pada
-- serahan_cash / permohonan_cuti / permohonan_padam / baucar_bayaran) tidak.
--
-- Penyelesaian: pencetus AFTER UPDATE OF status pada 6 jadual kelulusan:
--   serahan_cash, permohonan_cuti, permohonan_bayaran_hutang, serahan_produk,
--   permohonan_padam : menunggu -> disahkan / diluluskan / ditolak
--   baucar_bayaran   : draf     -> diluluskan / dibatalkan
-- (baucar dibayar & pembatalan automatik drpd diluluskan TIDAK diumumkan;
--  rekod yg terus dimasukkan sbg 'disahkan' (restock, pindah, padam_pulang) juga
--  bukan permohonan jadi tidak diumumkan.)
--
-- Elak pemakluman berganda utk keputusan Telegram (pencetus DAN webhook):
--   • rekod_pemakluman_kelulusan() kini: jika baris utk jadual+rekod yg sama
--     sudah dicipta < 2 minit & BELUM dihantar -> KEMAS KINI teksnya (teks
--     Telegram lebih lengkap); jika sudah dihantar -> langkau; jika tiada -> masuk.
--   • ambil_pemakluman_kelulusan() hanya ambil baris berumur > 15 saat supaya
--     webhook sempat menimpa teks.
-- Kegagalan pencetus TIDAK menghalang keputusan pemilik (EXCEPTION -> amaran).
-- Hanya keputusan BAHARU; keputusan lama tidak diumumkan semula.
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.pemakluman_keputusan()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
DECLARE
  v_n jsonb := to_jsonb(NEW);
  v_lulus boolean;
  v_pekerja text;
  v_pemilik text;
  v_tajuk text;
  v_butiran text;
  v_hasil text;
  v_sasaran text;
  v_masa text;
  v_tanda text;
  v_nota text;
BEGIN
  IF TG_TABLE_NAME = 'baucar_bayaran' THEN
    IF NOT (OLD.status = 'draf' AND NEW.status IN ('diluluskan','dibatalkan')) THEN RETURN NEW; END IF;
  ELSE
    IF NOT (OLD.status = 'menunggu' AND NEW.status IN ('disahkan','diluluskan','ditolak')) THEN RETURN NEW; END IF;
  END IF;
  v_lulus := NEW.status IN ('disahkan','diluluskan');
  v_tanda := CASE WHEN v_lulus THEN 'ok' ELSE 'ditolak' END;

  SELECT nama INTO v_pekerja FROM profiles WHERE id::text = v_n->>'pekerja_id';
  SELECT nama INTO v_pemilik FROM profiles
   WHERE id::text = COALESCE(auth.uid()::text, v_n->>'disahkan_oleh', v_n->>'diluluskan_oleh', v_n->>'diputuskan_oleh');
  v_nota := NULLIF(v_n->>'nota', '');

  IF TG_TABLE_NAME = 'serahan_cash' THEN
    v_tajuk := 'Serahan Cash';
    v_butiran := 'RM' || to_char((v_n->>'jumlah')::numeric, 'FM999999990.00') || COALESCE(E'\nNota: ' || v_nota, '');
    v_hasil := 'Serahan cash ' || CASE WHEN v_lulus THEN 'disahkan ✅' ELSE 'ditolak ✕' END;

  ELSIF TG_TABLE_NAME = 'permohonan_cuti' THEN
    v_tajuk := COALESCE(v_n->>'jenis', 'Cuti');
    v_butiran := to_char((v_n->>'tarikh_mula')::date, 'DD/MM/YYYY') || ' - ' || to_char((v_n->>'tarikh_tamat')::date, 'DD/MM/YYYY')
      || COALESCE(E'\nNota: ' || v_nota, '');
    v_hasil := 'Permohonan cuti/MC/off ' || CASE WHEN v_lulus THEN 'diluluskan ✅' ELSE 'ditolak ✕' END;

  ELSIF TG_TABLE_NAME = 'permohonan_bayaran_hutang' THEN
    IF v_n->>'kedai_id' IS NOT NULL THEN
      SELECT nama INTO v_sasaran FROM kedai WHERE id = v_n->>'kedai_id';
    END IF;
    v_sasaran := COALESCE(v_sasaran, COALESCE(v_n->>'nama_pembeli', '?') || ' (Peribadi)');
    v_tajuk := 'Bayaran Hutang';
    v_butiran := '🎯 ' || v_sasaran || E'\nRM' || to_char((v_n->>'jumlah')::numeric, 'FM999999990.00')
      || ' (' || COALESCE(v_n->>'kaedah_bayaran', '?') || ')'
      || CASE WHEN (v_n->>'settlement_penuh')::boolean THEN ' · PENUH' ELSE '' END;
    v_hasil := 'Bayaran hutang RM' || to_char((v_n->>'jumlah')::numeric, 'FM999999990.00') || ' ' || CASE WHEN v_lulus THEN 'disahkan ✅' ELSE 'ditolak ✕' END;

  ELSIF TG_TABLE_NAME = 'serahan_produk' THEN
    v_tajuk := CASE v_n->>'jenis'
      WHEN 'ambil' THEN 'Permohonan Ambil Stok'
      WHEN 'baik' THEN 'Serahan Produk (Baik)'
      WHEN 'reject' THEN 'Serahan Produk (Reject)'
      ELSE 'Serahan Produk (' || COALESCE(v_n->>'jenis', '?') || ')' END;
    v_butiran := COALESCE(v_n->>'stok_nama', '?') || ' ×' || COALESCE(v_n->>'kuantiti', '?')
      || COALESCE(E'\nSebab: ' || NULLIF(v_n->>'sebab', ''), '');
    v_hasil := 'Serahan produk (' || COALESCE(v_n->>'stok_nama', '?') || ' ×' || COALESCE(v_n->>'kuantiti', '?') || ') '
      || CASE WHEN v_lulus THEN 'disahkan ✅' ELSE 'ditolak ✕' END;

  ELSIF TG_TABLE_NAME = 'permohonan_padam' THEN
    v_tajuk := 'Permohonan Padam';
    v_butiran := COALESCE(v_n->>'rekod_label', v_n->>'rekod_id', '?') || ' (' || COALESCE(v_n->>'jenis', '?') || ')'
      || COALESCE(E'\nSebab: ' || NULLIF(v_n->>'sebab', ''), '');
    v_hasil := 'Permohonan padam ' || CASE WHEN v_lulus THEN 'diluluskan ✅' ELSE 'ditolak ✕' END;

  ELSIF TG_TABLE_NAME = 'baucar_bayaran' THEN
    v_tajuk := 'Baucar ' || replace(COALESCE(v_n->>'kategori', ''), '_', ' ');
    v_butiran := COALESCE(to_char((v_n->>'tarikh')::date, 'DD/MM/YYYY'), COALESCE(v_n->>'bulan', ''))
      || ' — RM' || to_char(COALESCE((v_n->>'jumlah')::numeric, 0), 'FM999999990.00')
      || COALESCE(E'\n' || NULLIF(v_n->>'tujuan', ''), '');
    v_hasil := 'Baucar ' || CASE WHEN v_lulus THEN 'diluluskan ✅' ELSE 'dibatalkan ✕' END;

  ELSE
    RETURN NEW;
  END IF;

  v_masa := to_char(now() AT TIME ZONE 'Asia/Kuala_Lumpur', 'DD/MM/YY, FMHH12:MI')
    || CASE WHEN extract(hour FROM (now() AT TIME ZONE 'Asia/Kuala_Lumpur')) < 12 THEN ' PG' ELSE ' PTG' END;

  INSERT INTO private.pemakluman_kelulusan (jadual, rekod_id, status, teks)
  VALUES (
    TG_TABLE_NAME, NEW.id::text, CASE WHEN v_lulus THEN 'disahkan' ELSE 'ditolak' END,
    '📢 *KELULUSAN PEMILIK — WAFI TIJARAH TRADING*' || E'\n\n'
      || '🔔 ' || v_tajuk || E'\n👤 ' || COALESCE(v_pekerja, '?') || E'\n' || v_butiran
      || E'\n\n➡️ ' || v_hasil || E'\n👤 oleh ' || COALESCE(v_pemilik, 'Pemilik') || ' · ' || v_masa
  );
  RETURN NEW;
EXCEPTION WHEN others THEN
  RAISE WARNING '[pemakluman_keputusan] gagal utk % %: %', TG_TABLE_NAME, NEW.id, SQLERRM;
  RETURN NEW;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.pemakluman_keputusan() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_pemakluman_keputusan ON public.serahan_cash;
CREATE TRIGGER trg_pemakluman_keputusan AFTER UPDATE OF status ON public.serahan_cash
  FOR EACH ROW WHEN (OLD.status IS DISTINCT FROM NEW.status) EXECUTE FUNCTION public.pemakluman_keputusan();
DROP TRIGGER IF EXISTS trg_pemakluman_keputusan ON public.permohonan_cuti;
CREATE TRIGGER trg_pemakluman_keputusan AFTER UPDATE OF status ON public.permohonan_cuti
  FOR EACH ROW WHEN (OLD.status IS DISTINCT FROM NEW.status) EXECUTE FUNCTION public.pemakluman_keputusan();
DROP TRIGGER IF EXISTS trg_pemakluman_keputusan ON public.permohonan_bayaran_hutang;
CREATE TRIGGER trg_pemakluman_keputusan AFTER UPDATE OF status ON public.permohonan_bayaran_hutang
  FOR EACH ROW WHEN (OLD.status IS DISTINCT FROM NEW.status) EXECUTE FUNCTION public.pemakluman_keputusan();
DROP TRIGGER IF EXISTS trg_pemakluman_keputusan ON public.serahan_produk;
CREATE TRIGGER trg_pemakluman_keputusan AFTER UPDATE OF status ON public.serahan_produk
  FOR EACH ROW WHEN (OLD.status IS DISTINCT FROM NEW.status) EXECUTE FUNCTION public.pemakluman_keputusan();
DROP TRIGGER IF EXISTS trg_pemakluman_keputusan ON public.permohonan_padam;
CREATE TRIGGER trg_pemakluman_keputusan AFTER UPDATE OF status ON public.permohonan_padam
  FOR EACH ROW WHEN (OLD.status IS DISTINCT FROM NEW.status) EXECUTE FUNCTION public.pemakluman_keputusan();
DROP TRIGGER IF EXISTS trg_pemakluman_keputusan ON public.baucar_bayaran;
CREATE TRIGGER trg_pemakluman_keputusan AFTER UPDATE OF status ON public.baucar_bayaran
  FOR EACH ROW WHEN (OLD.status IS DISTINCT FROM NEW.status) EXECUTE FUNCTION public.pemakluman_keputusan();

-- Webhook Telegram: timpa teks baris pencetus (lebih lengkap) ATAU langkau jika sudah dihantar
CREATE OR REPLACE FUNCTION public.rekod_pemakluman_kelulusan(p_jadual text, p_id text, p_status text, p_teks text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
DECLARE v_id bigint;
BEGIN
  SELECT id INTO v_id FROM private.pemakluman_kelulusan
   WHERE jadual = p_jadual AND rekod_id = p_id AND dihantar_pada IS NULL AND dicipta > now() - interval '2 minutes'
   ORDER BY id DESC LIMIT 1;
  IF v_id IS NOT NULL THEN
    UPDATE private.pemakluman_kelulusan SET teks = p_teks, status = p_status WHERE id = v_id;
    RETURN;
  END IF;
  IF EXISTS (SELECT 1 FROM private.pemakluman_kelulusan
              WHERE jadual = p_jadual AND rekod_id = p_id AND dicipta > now() - interval '2 minutes') THEN
    RETURN;
  END IF;
  INSERT INTO private.pemakluman_kelulusan (jadual, rekod_id, status, teks) VALUES (p_jadual, p_id, p_status, p_teks);
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.rekod_pemakluman_kelulusan(text, text, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rekod_pemakluman_kelulusan(text, text, text, text) TO service_role;

-- Skrip VPS: hanya baris berumur > 15 saat (beri masa webhook menimpa teks)
CREATE OR REPLACE FUNCTION public.ambil_pemakluman_kelulusan(p_kunci text)
RETURNS TABLE(id bigint, teks text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM private.api_kunci WHERE nama = 'pemakluman_kelulusan_wa' AND kunci = p_kunci) THEN
    RAISE EXCEPTION 'tidak dibenarkan';
  END IF;
  RETURN QUERY
    SELECT p.id, p.teks FROM private.pemakluman_kelulusan p
    WHERE p.dihantar_pada IS NULL AND p.dicipta > now() - interval '24 hours'
      AND p.dicipta < now() - interval '15 seconds'
    ORDER BY p.id LIMIT 20;
END $function$;

-- PEMBETULAN (selepas dijalankan): CREATE OR REPLACE di atas menggugurkan hak 'anon' pada
-- ambil_pemakluman_kelulusan sehingga skrip VPS (kunci anon) ditolak (42501). Pulihkan hak
-- asal SQL 150 (fungsi ini dilindungi kunci private.api_kunci, salah kunci = 'tidak dibenarkan'):
REVOKE EXECUTE ON FUNCTION public.ambil_pemakluman_kelulusan(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ambil_pemakluman_kelulusan(text) TO anon, authenticated;
