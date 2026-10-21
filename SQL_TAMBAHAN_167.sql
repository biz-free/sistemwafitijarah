-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 167 (LANGKAH B): pulihkan diskaun ikut tarikh_diterima — DRAF, BELUM DIAPPLY. Perlukan SQL 166 dulu.
--
-- MASALAH (kes Bukit Wang Harum, 21 Okt 2026): kedai transfer pada 20 Okt (hari
-- terakhir, diskaun 10% = RM540) tapi lambat inform. Bila pekerja key in esoknya,
-- cron lucuthak_diskaun_lewat_bayar() (00:30) sudah naikkan invois ke RM570 (5%),
-- jadi sistem anggap kedai bayar lewat / kurang.
--
-- PENYELESAIAN:
--   1) permohonan_bayaran_hutang.tarikh_diterima (date) — tarikh duit SEBENAR masuk.
--      Pekerja DAN pemilik wajib isi di borang (UI). Tak boleh akan datang; tak
--      boleh lebih 60 hari lepas. Data lama diisi = tarikh rekod dibuat (waktu MY).
--   2) pulih_diskaun_ikut_tarikh(kedai, jumlah, tarikh): sebelum bayaran diagih,
--      jika cron SUDAH turunkan diskaun invois skim tetapi tarikh_diterima masih
--      dalam tempoh diskaun, kadar dipulihkan — HANYA jika bayaran ini cukup
--      menjelaskan invois pada harga pulihan itu (bayaran separa tak pulihkan
--      diskaun). kedai.hutang dilaras sama.
--   3) mohon_bayaran_hutang(+p_tarikh_diterima), rekod_bayaran(+p_tarikh_diterima),
--      agih_bayaran_hutang(+p_tarikh_diterima) dan telegram_putuskan (lulus melalui
--      Telegram) guna tarikh ini. Tarikh disimpan pada permohonan, jadi permohonan
--      pekerja yg disahkan LEWAT oleh pemilik tetap guna tarikh duit masuk.
--   Had: invois belian peribadi (tanpa kedai) tidak dipulihkan diskaun — tarikh
--   tetap direkod sahaja.
-- ═══════════════════════════════════════════════════════════

-- ── Pulihkan diskaun skim jika duit sebenarnya diterima dalam tempoh diskaun ──
CREATE OR REPLACE FUNCTION public.pulih_diskaun_ikut_tarikh(p_kedai_id text, p_jumlah double precision, p_tarikh date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  t RECORD; m double precision := p_jumlah;
  v_hari_awal int; v_hari_akhir int; v_peratus_awal double precision; v_peratus_akhir double precision;
  v_layak double precision; v_jumlah_baru double precision; v_perlu double precision;
BEGIN
  IF p_kedai_id IS NULL OR p_tarikh IS NULL OR p_jumlah IS NULL OR p_jumlah <= 0 THEN RETURN; END IF;

  SELECT COALESCE(skim_hutang_hari_awal, 5), COALESCE(skim_hutang_hari_akhir, 7),
         COALESCE(skim_hutang_peratus_awal, 10), COALESCE(skim_hutang_peratus_akhir, 5)
    INTO v_hari_awal, v_hari_akhir, v_peratus_awal, v_peratus_akhir
    FROM tetapan WHERE id = 1;

  FOR t IN
    SELECT id, jumlah, jumlah_asal, jumlah_dibayar, diskaun_peratus, tarikh_akhir_bayaran FROM transaksi
    WHERE kedai_id = p_kedai_id AND status = 'hutang'
      AND skim_hutang_berperingkat AND tarikh_akhir_bayaran IS NOT NULL
    ORDER BY (kaedah_bayaran = 'consignment' AND jualan_disahkan IS NOT TRUE) ASC, tarikh_masa ASC
    FOR UPDATE
  LOOP
    EXIT WHEN m <= 0.005;
    v_layak := CASE
      WHEN p_tarikh <= t.tarikh_akhir_bayaran THEN v_peratus_awal
      WHEN p_tarikh <= t.tarikh_akhir_bayaran + GREATEST(v_hari_akhir - v_hari_awal, 0) THEN v_peratus_akhir
      ELSE 0 END;

    IF v_layak > t.diskaun_peratus THEN
      v_jumlah_baru := ROUND((t.jumlah_asal * (1 - v_layak / 100))::numeric, 2);
      v_perlu := GREATEST(v_jumlah_baru - t.jumlah_dibayar, 0);
      IF m >= v_perlu - 0.005 THEN
        UPDATE transaksi SET jumlah = v_jumlah_baru, diskaun_peratus = v_layak,
               diskaun_dilucuthak = (v_layak = 0)
         WHERE id = t.id;
        UPDATE kedai SET hutang = GREATEST(0, hutang - (t.jumlah - v_jumlah_baru)) WHERE id = p_kedai_id;
        m := m - v_perlu;
        CONTINUE;
      END IF;
    END IF;
    m := m - GREATEST(t.jumlah - t.jumlah_dibayar, 0);
  END LOOP;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.pulih_diskaun_ikut_tarikh(text, double precision, date) FROM PUBLIC, anon, authenticated;

-- ── rekod_bayaran: tambah p_tarikh_diterima (badan = SQL 164 + panggilan pulih) ──
DROP FUNCTION IF EXISTS public.rekod_bayaran(text, double precision);
CREATE OR REPLACE FUNCTION public.rekod_bayaran(p_kedai_id text, p_jumlah double precision, p_tarikh_diterima date DEFAULT NULL)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  baki float := p_jumlah; t RECORD; bayar float; hutang_baru float;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'pemilik') THEN
    RAISE EXCEPTION 'Hanya pemilik boleh rekod bayaran';
  END IF;
  IF p_jumlah IS NULL OR p_jumlah <= 0 THEN
    RAISE EXCEPTION 'Jumlah bayaran mesti lebih 0';
  END IF;

  PERFORM pulih_diskaun_ikut_tarikh(p_kedai_id, p_jumlah, p_tarikh_diterima);

  UPDATE kedai SET hutang = GREATEST(0, hutang - p_jumlah) WHERE id = p_kedai_id
    RETURNING hutang INTO hutang_baru;

  FOR t IN
    SELECT id, jumlah, jumlah_dibayar FROM transaksi
    WHERE kedai_id = p_kedai_id AND status = 'hutang'
    ORDER BY (kaedah_bayaran = 'consignment' AND jualan_disahkan IS NOT TRUE) ASC, tarikh_masa ASC
    FOR UPDATE
  LOOP
    EXIT WHEN baki <= 0.005;
    bayar := LEAST(baki, GREATEST(t.jumlah - t.jumlah_dibayar, 0));
    UPDATE transaksi SET
      jumlah_dibayar = jumlah_dibayar + bayar,
      status = CASE WHEN jumlah_dibayar + bayar >= jumlah - 0.005 THEN 'selesai' ELSE status END
    WHERE id = t.id;
    baki := baki - bayar;
  END LOOP;

  -- Hutang kedai sudah RM0 -> tiada invois hutang patut tinggal.
  IF COALESCE(hutang_baru, 1) <= 0.005 THEN
    UPDATE transaksi SET status = 'selesai', jumlah_dibayar = GREATEST(jumlah_dibayar, jumlah)
    WHERE kedai_id = p_kedai_id AND status = 'hutang';
  END IF;
END;
$function$;

-- ── agih_bayaran_hutang (laluan Telegram): tambah p_tarikh_diterima ──
DROP FUNCTION IF EXISTS public.agih_bayaran_hutang(text, text, double precision);
CREATE OR REPLACE FUNCTION public.agih_bayaran_hutang(p_kedai_id text, p_nama_pembeli text, p_jumlah double precision, p_tarikh_diterima date DEFAULT NULL)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE baki float := p_jumlah; t RECORD; bayar float; hutang_baru float;
BEGIN
  IF p_jumlah IS NULL OR p_jumlah <= 0 THEN RAISE EXCEPTION 'Jumlah bayaran mesti lebih 0'; END IF;

  IF p_kedai_id IS NOT NULL THEN
    PERFORM pulih_diskaun_ikut_tarikh(p_kedai_id, p_jumlah, p_tarikh_diterima);
    UPDATE kedai SET hutang = GREATEST(0, hutang - p_jumlah) WHERE id = p_kedai_id
      RETURNING hutang INTO hutang_baru;
  END IF;

  FOR t IN
    SELECT id, jumlah, jumlah_dibayar FROM transaksi
    WHERE status = 'hutang'
      AND CASE WHEN p_kedai_id IS NOT NULL THEN kedai_id = p_kedai_id
               ELSE kedai_id IS NULL AND nama_pembeli = p_nama_pembeli END
    ORDER BY tarikh_masa ASC
    FOR UPDATE
  LOOP
    EXIT WHEN baki <= 0.005;
    bayar := LEAST(baki, GREATEST(t.jumlah - t.jumlah_dibayar, 0));
    UPDATE transaksi SET
      jumlah_dibayar = jumlah_dibayar + bayar,
      status = CASE WHEN jumlah_dibayar + bayar >= jumlah - 0.005 THEN 'selesai' ELSE status END
    WHERE id = t.id;
    baki := baki - bayar;
  END LOOP;

  IF p_kedai_id IS NOT NULL AND COALESCE(hutang_baru, 1) <= 0.005 THEN
    UPDATE transaksi SET status = 'selesai', jumlah_dibayar = GREATEST(jumlah_dibayar, jumlah)
    WHERE kedai_id = p_kedai_id AND status = 'hutang';
  END IF;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.agih_bayaran_hutang(text, text, double precision, date) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.agih_bayaran_hutang(text, text, double precision, date) TO service_role;

-- ── mohon_bayaran_hutang: tambah p_tarikh_diterima (badan = definisi live + tarikh) ──
DROP FUNCTION IF EXISTS public.mohon_bayaran_hutang(text, text, double precision, text, text, text, boolean, text);
CREATE OR REPLACE FUNCTION public.mohon_bayaran_hutang(
  p_id text, p_kedai_id text, p_jumlah double precision, p_kaedah_bayaran text,
  p_resit_bukti_url text DEFAULT NULL, p_nota text DEFAULT NULL,
  p_settlement_penuh boolean DEFAULT false, p_nama_pembeli text DEFAULT NULL,
  p_tarikh_diterima date DEFAULT NULL)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_hari date := (now() AT TIME ZONE 'Asia/Kuala_Lumpur')::date;
  v_tarikh date := COALESCE(p_tarikh_diterima, (now() AT TIME ZONE 'Asia/Kuala_Lumpur')::date);
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Log masuk diperlukan'; END IF;
  IF p_jumlah <= 0 THEN RAISE EXCEPTION 'Jumlah mesti lebih 0'; END IF;
  IF p_kaedah_bayaran NOT IN ('tunai','transfer') THEN RAISE EXCEPTION 'Kaedah bayaran tidak sah'; END IF;
  IF (p_kedai_id IS NOT NULL) = (p_nama_pembeli IS NOT NULL) THEN
    RAISE EXCEPTION 'Perlu tepat satu: kedai ATAU nama pembeli peribadi';
  END IF;
  IF v_tarikh > v_hari THEN RAISE EXCEPTION 'Tarikh duit diterima tidak boleh akan datang'; END IF;
  IF v_tarikh < v_hari - 60 THEN RAISE EXCEPTION 'Tarikh duit diterima terlalu lama (maksimum 60 hari lepas)'; END IF;

  IF is_pemilik() THEN
    IF p_kedai_id IS NOT NULL THEN
      IF p_settlement_penuh THEN
        PERFORM rekod_bayaran_penuh(p_kedai_id);
      ELSE
        PERFORM rekod_bayaran(p_kedai_id, p_jumlah, v_tarikh);
      END IF;
    ELSE
      IF p_settlement_penuh THEN
        PERFORM rekod_bayaran_penuh_peribadi(p_nama_pembeli);
      ELSE
        PERFORM rekod_bayaran_peribadi(p_nama_pembeli, p_jumlah);
      END IF;
    END IF;
    INSERT INTO permohonan_bayaran_hutang (id, kedai_id, nama_pembeli, pekerja_id, jumlah, kaedah_bayaran, resit_bukti_url, nota, settlement_penuh, status, disahkan_oleh, disahkan_pada, tarikh_diterima)
    VALUES (p_id, p_kedai_id, p_nama_pembeli, auth.uid(), p_jumlah, p_kaedah_bayaran, p_resit_bukti_url, p_nota, p_settlement_penuh, 'disahkan', auth.uid(), now(), v_tarikh);
  ELSE
    INSERT INTO permohonan_bayaran_hutang (id, kedai_id, nama_pembeli, pekerja_id, jumlah, kaedah_bayaran, resit_bukti_url, nota, settlement_penuh, tarikh_diterima)
    VALUES (p_id, p_kedai_id, p_nama_pembeli, auth.uid(), p_jumlah, p_kaedah_bayaran, p_resit_bukti_url, p_nota, p_settlement_penuh, v_tarikh);
  END IF;
END;
$function$;

-- ── putuskan_bayaran_hutang (web, pemilik sahkan permohonan pekerja): guna tarikh simpanan ──
CREATE OR REPLACE FUNCTION public.putuskan_bayaran_hutang(p_id text, p_status text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_row permohonan_bayaran_hutang%ROWTYPE;
BEGIN
  IF NOT is_pemilik() THEN RAISE EXCEPTION 'Hanya pemilik boleh putuskan permohonan bayaran'; END IF;
  IF p_status NOT IN ('disahkan','ditolak') THEN RAISE EXCEPTION 'Status tidak sah'; END IF;

  SELECT * INTO v_row FROM permohonan_bayaran_hutang WHERE id = p_id AND status = 'menunggu';
  IF NOT FOUND THEN RAISE EXCEPTION 'Permohonan tidak dijumpai atau sudah diputuskan'; END IF;

  IF p_status = 'disahkan' THEN
    IF v_row.kedai_id IS NOT NULL THEN
      IF v_row.settlement_penuh THEN
        PERFORM rekod_bayaran_penuh(v_row.kedai_id);
      ELSE
        PERFORM rekod_bayaran(v_row.kedai_id, v_row.jumlah, v_row.tarikh_diterima);
      END IF;
    ELSE
      IF v_row.settlement_penuh THEN
        PERFORM rekod_bayaran_penuh_peribadi(v_row.nama_pembeli);
      ELSE
        PERFORM rekod_bayaran_peribadi(v_row.nama_pembeli, v_row.jumlah);
      END IF;
    END IF;
  END IF;

  UPDATE permohonan_bayaran_hutang SET status = p_status, disahkan_oleh = auth.uid(), disahkan_pada = now() WHERE id = p_id;
END;
$function$;

-- ── telegram_putuskan: hantar tarikh_diterima ke agih_bayaran_hutang ──
-- Ubah suai definisi LIVE (tak salin semula fungsi panjang): gantikan panggilan
-- agih_bayaran_hutang utk kedai. Gagal (rollback) jika corak tak dijumpai.
DO $$
DECLARE v_def text; v_baru text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'telegram_putuskan';
  v_baru := replace(v_def, 'agih_bayaran_hutang(v_row.kedai_id, NULL, v_row.jumlah)',
                           'agih_bayaran_hutang(v_row.kedai_id, NULL, v_row.jumlah, v_row.tarikh_diterima)');
  IF v_baru = v_def THEN
    RAISE EXCEPTION 'telegram_putuskan: corak agih_bayaran_hutang(kedai) tidak dijumpai';
  END IF;
  EXECUTE v_baru;
END $$;
