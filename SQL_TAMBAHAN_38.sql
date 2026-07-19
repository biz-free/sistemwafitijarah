-- SQL_TAMBAHAN_38: Pembetulan Padam Voucher + Had Maksima Belanja
--
-- BUG DIBETULKAN: padam voucher yang PERNAH digunakan (ada rekod di
-- baucar_guna) gagal dengan ralat foreign key — sebab FK baucar_guna.kod
-- tiada ON DELETE CASCADE. Dibetulkan supaya padam voucher turut padam
-- rekod penggunaan berkaitan (tiada kesan pada pesanan sedia ada, cuma
-- rekod "siapa dah guna kod ni" untuk kod yang dipadam).

ALTER TABLE baucar_guna DROP CONSTRAINT IF EXISTS baucar_guna_kod_fkey;
ALTER TABLE baucar_guna ADD CONSTRAINT baucar_guna_kod_fkey
  FOREIGN KEY (kod) REFERENCES baucar(kod) ON DELETE CASCADE;

-- Had Maksima Belanja: elak voucher digunakan untuk belian bernilai terlalu besar
ALTER TABLE baucar ADD COLUMN IF NOT EXISTS maksima_belanja float;

CREATE OR REPLACE FUNCTION validasi_baucar(p_kod text, p_telefon text, p_subjumlah float)
RETURNS TABLE(sah boolean, mesej text, diskaun float, jenis_diskaun text, nilai_diskaun float)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_baucar RECORD; v_diskaun float;
BEGIN
  SELECT * INTO v_baucar FROM baucar WHERE kod = upper(trim(p_kod)) FOR UPDATE;
  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'Kod voucher tidak sah', 0::float, NULL::text, NULL::float; RETURN;
  END IF;
  IF NOT v_baucar.aktif THEN
    RETURN QUERY SELECT false, 'Kod voucher tidak aktif', 0::float, NULL::text, NULL::float; RETURN;
  END IF;
  IF v_baucar.tarikh_luput IS NOT NULL AND v_baucar.tarikh_luput < CURRENT_DATE THEN
    RETURN QUERY SELECT false, 'Kod voucher telah luput', 0::float, NULL::text, NULL::float; RETURN;
  END IF;
  IF p_subjumlah < COALESCE(v_baucar.minima_belanja,0) THEN
    RETURN QUERY SELECT false, format('Perlu belanja minimum RM%s untuk guna kod ini', v_baucar.minima_belanja), 0::float, NULL::text, NULL::float; RETURN;
  END IF;
  IF v_baucar.maksima_belanja IS NOT NULL AND p_subjumlah > v_baucar.maksima_belanja THEN
    RETURN QUERY SELECT false, format('Kod ini hanya sah untuk belian sehingga RM%s', v_baucar.maksima_belanja), 0::float, NULL::text, NULL::float; RETURN;
  END IF;
  IF v_baucar.had_guna IS NOT NULL AND v_baucar.bilangan_guna >= v_baucar.had_guna THEN
    RETURN QUERY SELECT false, 'Kod voucher telah mencapai had penggunaan', 0::float, NULL::text, NULL::float; RETURN;
  END IF;
  IF EXISTS (SELECT 1 FROM baucar_guna WHERE kod = v_baucar.kod AND telefon = p_telefon) THEN
    RETURN QUERY SELECT false, 'Anda sudah guna kod voucher ini sebelum ini', 0::float, NULL::text, NULL::float; RETURN;
  END IF;

  v_diskaun := CASE WHEN v_baucar.jenis_diskaun = 'tetap' THEN v_baucar.nilai_diskaun
                     ELSE p_subjumlah * v_baucar.nilai_diskaun / 100 END;
  v_diskaun := LEAST(v_diskaun, p_subjumlah);
  RETURN QUERY SELECT true, 'Kod voucher sah', v_diskaun, v_baucar.jenis_diskaun, v_baucar.nilai_diskaun;
END; $$;
