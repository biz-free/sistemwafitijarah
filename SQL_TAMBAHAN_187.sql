-- SQL 187: Toleransi pembundaran 5 sen pada kutipan hutang kedai (DRAF, belum dijalankan)
--
-- Masalah: bayaran tunai dibundarkan ke 5 sen terdekat (cth invois RM317.52, kedai bayar RM317.50).
-- Sebelum ini hanya baki <= RM0.005 dianggap langsai, jadi baki 2 sen kekal sebagai hutang
-- dan akaun pekerja tidak tally.
--
-- Perubahan: jika selepas bayaran baki hutang kedai <= RM0.04 (kurang daripada satu langkah
-- pembundaran 5 sen), baki dianggap langsai: kedai.hutang = 0 dan semua invois hutang kedai itu
-- ditutup (status 'selesai'). Logik lain TIDAK diubah.
--
-- Fungsi terlibat: rekod_bayaran, agih_bayaran_hutang (badan fungsi sama seperti dalam DB,
-- hanya blok penutup baki di hujung diubah). rekod_bayaran_peribadi tidak disentuh (tiada rekod kedai).
--
-- Kesan sampingan: jumlah_dibayar invois dinaikkan ke jumlah penuh, jadi RM0.02 dikira "dibayar"
-- walaupun tidak diterima. Ia pelarasan pembundaran dan tiada jejak berasingan.

CREATE OR REPLACE FUNCTION public.rekod_bayaran(p_kedai_id text, p_jumlah double precision, p_tarikh_diterima date DEFAULT NULL::date)
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

  -- Toleransi pembundaran 5 sen: baki <= RM0.04 dianggap langsai
  IF COALESCE(hutang_baru, 1) <= 0.04 THEN
    UPDATE kedai SET hutang = 0 WHERE id = p_kedai_id AND hutang > 0;
    UPDATE transaksi SET status = 'selesai', jumlah_dibayar = GREATEST(jumlah_dibayar, jumlah)
    WHERE kedai_id = p_kedai_id AND status = 'hutang';
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.agih_bayaran_hutang(p_kedai_id text, p_nama_pembeli text, p_jumlah double precision, p_tarikh_diterima date DEFAULT NULL::date)
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

  -- Toleransi pembundaran 5 sen: baki <= RM0.04 dianggap langsai
  IF p_kedai_id IS NOT NULL AND COALESCE(hutang_baru, 1) <= 0.04 THEN
    UPDATE kedai SET hutang = 0 WHERE id = p_kedai_id AND hutang > 0;
    UPDATE transaksi SET status = 'selesai', jumlah_dibayar = GREATEST(jumlah_dibayar, jumlah)
    WHERE kedai_id = p_kedai_id AND status = 'hutang';
  END IF;
END;
$function$;
