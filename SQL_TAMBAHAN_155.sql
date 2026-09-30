-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 155: Betulkan rekod bayaran hutang yang tersilap
-- (kaedah bayaran dan/atau pekerja yang dikaitkan).
--
-- PUNCA (aduan Amirul, kes Pasar Mini Segar Muzakkir RM50): bila
-- Pemilik sendiri yang rekod "Terima Bayaran Hutang" (bukan pekerja
-- hantar permohonan), mohon_bayaran_hutang() catat pekerja_id =
-- akaun PEMILIK sendiri (sebab dia yang panggil RPC tu), bukan
-- pekerja yang sebenarnya kutip/pegang duit tunai di lapangan (cth
-- Nadia). Akibatnya kiraCashDipegang() salah anggap PEMILIK yang
-- pegang cash, bukan pekerja sebenar — tiada cara betulkan sebelum
-- ini bila kesilapan macam ni berlaku, atau bila duit tunai yang
-- direkod kemudian didapati sudah dibank-in terus (patut jadi
-- 'transfer', bukan 'tunai', supaya tak dikira lagi sebagai cash
-- belum diserah).
--
-- Fungsi ni Pemilik SAHAJA, cuma boleh ubah rekod yg status='disahkan'
-- (rekod 'menunggu' guna putuskan_bayaran_hutang sedia ada; rekod
-- 'ditolak' tak relevan lagi). p_kaedah_bayaran_baru & p_pekerja_id_baru
-- kedua-dua PILIHAN (boleh betulkan satu sahaja atau kedua-dua sekali).
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.betulkan_bayaran_hutang_diterima(
  p_id text,
  p_kaedah_bayaran_baru text DEFAULT NULL,
  p_pekerja_id_baru uuid DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public' AS $$
DECLARE v_row permohonan_bayaran_hutang%ROWTYPE;
BEGIN
  IF NOT is_pemilik() THEN RAISE EXCEPTION 'Hanya pemilik boleh betulkan rekod bayaran'; END IF;
  IF p_kaedah_bayaran_baru IS NULL AND p_pekerja_id_baru IS NULL THEN
    RAISE EXCEPTION 'Tiada apa-apa untuk dibetulkan';
  END IF;
  IF p_kaedah_bayaran_baru IS NOT NULL AND p_kaedah_bayaran_baru NOT IN ('tunai','transfer') THEN
    RAISE EXCEPTION 'Kaedah bayaran tidak sah';
  END IF;

  SELECT * INTO v_row FROM permohonan_bayaran_hutang WHERE id = p_id AND status = 'disahkan';
  IF NOT FOUND THEN RAISE EXCEPTION 'Rekod bayaran (disahkan) tidak dijumpai'; END IF;

  IF p_pekerja_id_baru IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = p_pekerja_id_baru) THEN
      RAISE EXCEPTION 'Pekerja tidak dijumpai';
    END IF;
  END IF;

  UPDATE permohonan_bayaran_hutang SET
    kaedah_bayaran = COALESCE(p_kaedah_bayaran_baru, kaedah_bayaran),
    pekerja_id = COALESCE(p_pekerja_id_baru, pekerja_id)
  WHERE id = p_id;
END;
$$;
REVOKE ALL ON FUNCTION public.betulkan_bayaran_hutang_diterima(text, text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.betulkan_bayaran_hutang_diterima(text, text, uuid) TO authenticated;
