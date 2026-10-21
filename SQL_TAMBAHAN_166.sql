-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 166 (LANGKAH A): simpan tarikh duit hutang DITERIMA — DRAF, BELUM DIAPPLY.
--
-- Tambah permohonan_bayaran_hutang.tarikh_diterima (date) dan terima p_tarikh_diterima
-- dalam mohon_bayaran_hutang(). Tarikh hanya DISIMPAN & disahkan (tak boleh akan
-- datang, tak boleh lebih 60 hari lepas). TIADA perubahan pada cara hutang/diskaun
-- dikira — pemulihan diskaun ikut tarikh ada di SQL 167 (Langkah B).
-- Data lama diisi = tarikh rekod dibuat (waktu Malaysia).
-- ═══════════════════════════════════════════════════════════

ALTER TABLE public.permohonan_bayaran_hutang ADD COLUMN IF NOT EXISTS tarikh_diterima date;
UPDATE public.permohonan_bayaran_hutang
   SET tarikh_diterima = (created_at AT TIME ZONE 'Asia/Kuala_Lumpur')::date
 WHERE tarikh_diterima IS NULL;
ALTER TABLE public.permohonan_bayaran_hutang ALTER COLUMN tarikh_diterima SET NOT NULL;
ALTER TABLE public.permohonan_bayaran_hutang
  ALTER COLUMN tarikh_diterima SET DEFAULT ((now() AT TIME ZONE 'Asia/Kuala_Lumpur')::date);

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
        PERFORM rekod_bayaran(p_kedai_id, p_jumlah);
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
