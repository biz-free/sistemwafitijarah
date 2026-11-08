-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 185: Kod affiliate SENTIASA dijana automatik; affiliate boleh
-- tukar sendiri tetapi DITOLAK jika ada sebarang ruang kosong (space/tab/baris baru)
-- ═══════════════════════════════════════════════════════════
-- 1) lulus_permohonan_affiliate (kelulusan melalui web): sebelum ini pemilik
--    taip kod secara manual (boleh ada ruang, cth "RAUDHAH OSMAN"). Kini kod
--    dijana automatik drpd perkataan pertama nama (huruf sahaja, huruf besar),
--    + nombor jika sudah dipakai — sama seperti kelulusan melalui Telegram
--    (SQL 163). Parameter p_kod_affiliate dikekalkan utk keserasian tetapi DIABAIKAN.
-- 2) kemaskini_kod_affiliate_sendiri: sebelum ini trim() senyap-senyap
--    membuang ruang di hujung. Kini input mentah yg mengandungi sebarang
--    ruang kosong ditolak terus.

CREATE OR REPLACE FUNCTION public.jana_kod_affiliate(p_nama text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_kod text; v_cuba text; v_n int := 1;
BEGIN
  v_kod := upper(regexp_replace(split_part(trim(COALESCE(p_nama,'')), ' ', 1), '[^A-Za-z]', '', 'g'));
  IF v_kod = '' THEN v_kod := 'AFF'; END IF;
  v_kod := left(v_kod, 16);
  v_cuba := v_kod;
  WHILE EXISTS (SELECT 1 FROM affiliates WHERE kod_affiliate = v_cuba) LOOP
    v_n := v_n + 1;
    v_cuba := v_kod || v_n;
  END LOOP;
  RETURN v_cuba;
END; $$;
REVOKE ALL ON FUNCTION public.jana_kod_affiliate(text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.lulus_permohonan_affiliate(p_id uuid, p_kod_affiliate text, p_kadar_komisen numeric, p_kadar_diskaun numeric, p_minima_belian numeric DEFAULT 500)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_nama text; v_kod text;
BEGIN
  IF NOT is_pemilik() THEN RAISE EXCEPTION 'Hanya pemilik boleh meluluskan permohonan affiliate'; END IF;
  IF p_kadar_komisen < 0 OR p_kadar_komisen > 100 THEN RAISE EXCEPTION 'Kadar komisen tidak sah'; END IF;
  IF p_kadar_diskaun < 0 OR p_kadar_diskaun > 100 THEN RAISE EXCEPTION 'Kadar diskaun tidak sah'; END IF;
  IF p_minima_belian < 0 THEN RAISE EXCEPTION 'Minima belian tidak sah'; END IF;
  SELECT nama INTO v_nama FROM affiliates WHERE id = p_id AND status = 'menunggu' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Permohonan tidak dijumpai atau sudah diproses'; END IF;
  v_kod := jana_kod_affiliate(v_nama);
  UPDATE affiliates SET
    kod_affiliate = v_kod, kadar_komisen_peratus = p_kadar_komisen,
    kadar_diskaun_peratus = p_kadar_diskaun, minima_belian = p_minima_belian, status = 'aktif',
    disahkan_oleh = auth.uid(), disahkan_pada = now()
  WHERE id = p_id AND status = 'menunggu';
END; $$;

CREATE OR REPLACE FUNCTION public.kemaskini_kod_affiliate_sendiri(p_kod_baharu text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_status text; v_kod text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Log masuk diperlukan'; END IF;
  IF COALESCE(p_kod_baharu, '') = '' THEN RAISE EXCEPTION 'Kod tidak boleh kosong'; END IF;
  IF p_kod_baharu ~ '\s' THEN RAISE EXCEPTION 'Kod tidak boleh mengandungi ruang kosong (space)'; END IF;
  v_kod := upper(p_kod_baharu);
  IF v_kod !~ '^[A-Z0-9]+$' THEN RAISE EXCEPTION 'Kod hanya boleh mengandungi huruf dan nombor (tiada ruang/simbol)'; END IF;
  IF length(v_kod) < 3 THEN RAISE EXCEPTION 'Kod terlalu pendek (minimum 3 aksara)'; END IF;
  IF length(v_kod) > 20 THEN RAISE EXCEPTION 'Kod terlalu panjang (maksimum 20 aksara)'; END IF;

  SELECT status INTO v_status FROM affiliates WHERE id = auth.uid();
  IF v_status IS DISTINCT FROM 'aktif' THEN RAISE EXCEPTION 'Akaun affiliate anda tidak aktif'; END IF;

  IF EXISTS (SELECT 1 FROM affiliates WHERE kod_affiliate = v_kod AND id <> auth.uid()) THEN
    RAISE EXCEPTION 'Kod "%" sudah digunakan oleh affiliate lain — sila pilih kod lain', v_kod;
  END IF;

  UPDATE affiliates SET kod_affiliate = v_kod WHERE id = auth.uid();
END; $$;
GRANT EXECUTE ON FUNCTION public.kemaskini_kod_affiliate_sendiri(text) TO authenticated;
