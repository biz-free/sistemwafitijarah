-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 159: Bayaran SEPARA kini dikumpul pada invois — invois ditukar
-- kepada resit (status 'selesai') bila jumlah terkumpul mencukupi.
--
-- PUNCA (kes Pasaraya Arisya, Okt 2026): rekod_bayaran() hanya tandakan invois
-- 'selesai' jika SATU bayaran menampung keseluruhan jumlah invois itu. Bayaran
-- separa (cth RM453.60 ke atas invois RM504, kemudian baki RM50.40) hanya
-- mengurangkan kedai.hutang tetapi tak diingati pada invois -> hutang kedai RM0
-- tetapi invois kekal 'hutang' selama-lamanya & paparan hutang tak turun.
--
-- PEMBETULAN:
--   1. Lajur transaksi.jumlah_dibayar — bayaran dikumpul ikut invois (FIFO, paling
--      lama dahulu). Invois 'selesai' bila jumlah_dibayar >= jumlah.
--   2. Jika kedai.hutang mencecah RM0 selepas bayaran, SEMUA invois hutang kedai itu
--      ditanda selesai (selaras dgn rekod_bayaran_penuh) — jaring keselamatan utk
--      bayaran separa lama yang tak pernah dijejak.
--   3. Sama utk pembelian peribadi (rekod_bayaran_peribadi).
-- Diskaun yg dilucuthak selepas bayaran separa (SQL 107/156) tetap betul: baki
-- invois = jumlah - jumlah_dibayar.
-- ═══════════════════════════════════════════════════════════

ALTER TABLE public.transaksi ADD COLUMN IF NOT EXISTS jumlah_dibayar double precision NOT NULL DEFAULT 0;

CREATE OR REPLACE FUNCTION public.rekod_bayaran(p_kedai_id text, p_jumlah double precision)
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

  UPDATE kedai SET hutang = GREATEST(0, hutang - p_jumlah) WHERE id = p_kedai_id
    RETURNING hutang INTO hutang_baru;

  FOR t IN
    SELECT id, jumlah, jumlah_dibayar FROM transaksi
    WHERE kedai_id = p_kedai_id AND status = 'hutang'
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

  -- Hutang kedai sudah RM0 -> tiada invois hutang patut tinggal.
  IF COALESCE(hutang_baru, 1) <= 0.005 THEN
    UPDATE transaksi SET status = 'selesai', jumlah_dibayar = GREATEST(jumlah_dibayar, jumlah)
    WHERE kedai_id = p_kedai_id AND status = 'hutang';
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.rekod_bayaran_peribadi(p_nama_pembeli text, p_jumlah double precision)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE baki float := p_jumlah; t RECORD; bayar float;
BEGIN
  IF NOT is_pemilik() THEN RAISE EXCEPTION 'Hanya pemilik boleh rekod bayaran'; END IF;
  IF p_jumlah IS NULL OR p_jumlah <= 0 THEN RAISE EXCEPTION 'Jumlah bayaran mesti lebih 0'; END IF;
  FOR t IN
    SELECT id, jumlah, jumlah_dibayar FROM transaksi
    WHERE kedai_id IS NULL AND nama_pembeli = p_nama_pembeli AND status = 'hutang'
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
END; $function$;
