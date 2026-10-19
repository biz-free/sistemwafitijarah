-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 164: Agihan bayaran hutang (FIFO) dahulukan invois hutang sebenar;
-- consignment yang belum disahkan terjual diletak PALING AKHIR.
--
-- PUNCA: rekod_bayaran() (SQL 159, web) dan agih_bayaran_hutang() (SQL 162, Telegram)
-- susun invois status='hutang' ikut tarikh_masa ASC sahaja. Jika consignment lama yang
-- belum disahkan (kaedah_bayaran='consignment', jualan_disahkan=false) wujud bersama
-- hutang sebenar yang lebih baharu, bayaran masuk ke consignment dahulu — jumlah
-- hutang kedai tetap betul tetapi invois yang ditanda lunas tersasar.
--
-- PEMBETULAN: tambah kunci isihan pertama — consignment belum disahkan = 1, selain itu
-- = 0 — sebelum tarikh_masa. TIADA invois dilangkau, jadi semua bayaran tetap diagihkan
-- (lebihan masih jatuh ke consignment selepas hutang sebenar habis) dan jumlah kedai.hutang
-- tidak berubah. Hanya urutan berubah. Bahagian lain kedua-dua fungsi KEKAL sama dgn
-- SQL 159 / 162 (disemak sama dgn definisi live pada 19 Okt 2026).
-- Tiada data sedia ada diubah. Kes semasa: tiada kedai terkesan.
-- ═══════════════════════════════════════════════════════════

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

CREATE OR REPLACE FUNCTION public.agih_bayaran_hutang(p_kedai_id text, p_nama_pembeli text, p_jumlah double precision)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE baki float := p_jumlah; t RECORD; bayar float; hutang_baru float;
BEGIN
  IF p_jumlah IS NULL OR p_jumlah <= 0 THEN RAISE EXCEPTION 'Jumlah bayaran mesti lebih 0'; END IF;

  IF p_kedai_id IS NOT NULL THEN
    UPDATE kedai SET hutang = GREATEST(0, hutang - p_jumlah) WHERE id = p_kedai_id
      RETURNING hutang INTO hutang_baru;
  END IF;

  FOR t IN
    SELECT id, jumlah, jumlah_dibayar FROM transaksi
    WHERE status = 'hutang'
      AND CASE WHEN p_kedai_id IS NOT NULL THEN kedai_id = p_kedai_id
               ELSE kedai_id IS NULL AND nama_pembeli = p_nama_pembeli END
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

  IF p_kedai_id IS NOT NULL AND COALESCE(hutang_baru, 1) <= 0.005 THEN
    UPDATE transaksi SET status = 'selesai', jumlah_dibayar = GREATEST(jumlah_dibayar, jumlah)
    WHERE kedai_id = p_kedai_id AND status = 'hutang';
  END IF;
END;
$function$;

-- Kekalkan keizinan SQL 162 (CREATE OR REPLACE tak ubah grant, ditulis semula utk jelas).
REVOKE EXECUTE ON FUNCTION public.agih_bayaran_hutang(text, text, double precision) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.agih_bayaran_hutang(text, text, double precision) TO service_role;
