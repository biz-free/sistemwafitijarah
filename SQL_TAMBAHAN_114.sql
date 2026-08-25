-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 114: Affiliate boleh tukar kod affiliate sendiri
-- ═══════════════════════════════════════════════════════════
-- Sebelum ini kod_affiliate hanya ditetapkan SEKALI oleh pemilik semasa lulus
-- permohonan (lulus_permohonan_affiliate) — affiliate tiada cara tukar sendiri
-- kalau nak kod lebih personal/mudah diingati. RPC ni bagi affiliate (status
-- 'aktif' sahaja) tukar kod sendiri, dengan semakan unik (kod_affiliate UNIQUE
-- di jadual affiliates) & format bersih (huruf/nombor sahaja, sesuai utk URL
-- ?affiliate=KOD & checkout).
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.kemaskini_kod_affiliate_sendiri(p_kod_baharu text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_status text; v_kod text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Log masuk diperlukan'; END IF;
  v_kod := upper(trim(COALESCE(p_kod_baharu, '')));
  IF v_kod = '' THEN RAISE EXCEPTION 'Kod tidak boleh kosong'; END IF;
  IF v_kod !~ '^[A-Z0-9]+$' THEN RAISE EXCEPTION 'Kod hanya boleh mengandungi huruf dan nombor (tiada ruang/simbol)'; END IF;
  IF length(v_kod) > 20 THEN RAISE EXCEPTION 'Kod terlalu panjang (maksimum 20 aksara)'; END IF;

  SELECT status INTO v_status FROM affiliates WHERE id = auth.uid();
  IF v_status IS DISTINCT FROM 'aktif' THEN RAISE EXCEPTION 'Akaun affiliate anda tidak aktif'; END IF;

  IF EXISTS (SELECT 1 FROM affiliates WHERE kod_affiliate = v_kod AND id <> auth.uid()) THEN
    RAISE EXCEPTION 'Kod "%" sudah digunakan oleh affiliate lain — sila pilih kod lain', v_kod;
  END IF;

  UPDATE affiliates SET kod_affiliate = v_kod WHERE id = auth.uid();
END; $$;
GRANT EXECUTE ON FUNCTION public.kemaskini_kod_affiliate_sendiri(text) TO authenticated;
