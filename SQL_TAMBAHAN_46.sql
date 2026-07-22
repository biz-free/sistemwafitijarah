-- SQL_TAMBAHAN_46: Daftar Nombor Rujukan Manual (pemilik)
--
-- Kod rujukan "Bawa Kawan" asalnya hanya sah untuk nombor telefon pelanggan
-- yang PERNAH beli & disahkan bayar (SQL_TAMBAHAN_45). Ini tambah OPTION
-- KEDUA: pemilik boleh daftar terus mana-mana nombor telefon (cth staf,
-- influencer, rakan niaga) sebagai kod rujukan sah, TANPA perlu nombor itu
-- pernah membeli — berguna untuk kempen rujukan luar (bukan pelanggan sedia
-- ada sahaja).

CREATE TABLE IF NOT EXISTS rujukan_manual (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  telefon text NOT NULL UNIQUE,
  nama text,
  emel text,
  aktif boolean NOT NULL DEFAULT true,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE rujukan_manual ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "pemilik urus rujukan_manual" ON rujukan_manual;
CREATE POLICY "pemilik urus rujukan_manual" ON rujukan_manual FOR ALL USING (is_pemilik()) WITH CHECK (is_pemilik());

-- Kemaskini validasi_rujukan() supaya turut terima nombor daftar manual
-- (selain nombor pelanggan sedia ada yang pernah disahkan bayar).
CREATE OR REPLACE FUNCTION validasi_rujukan(p_kod_rujukan text, p_telefon_pembeli text)
RETURNS TABLE(sah boolean, mesej text, diskaun_peratus float)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_telefon_rujukan text;
  v_telefon_pembeli text;
  v_aktif boolean;
  v_peratus float;
  v_wujud boolean;
BEGIN
  SELECT rujukan_aktif, rujukan_diskaun_kawan_peratus INTO v_aktif, v_peratus FROM tetapan WHERE id = 1;
  IF NOT COALESCE(v_aktif, true) THEN
    RETURN QUERY SELECT false, 'Program rujukan tidak aktif', NULL::float; RETURN;
  END IF;

  v_telefon_rujukan := regexp_replace(trim(p_kod_rujukan), '[^0-9]', '', 'g');
  v_telefon_pembeli := regexp_replace(trim(p_telefon_pembeli), '[^0-9]', '', 'g');
  IF v_telefon_rujukan = '' THEN
    RETURN QUERY SELECT false, 'Kod rujukan tidak sah', NULL::float; RETURN;
  END IF;
  IF v_telefon_rujukan = v_telefon_pembeli THEN
    RETURN QUERY SELECT false, 'Tidak boleh guna nombor sendiri sebagai kod rujukan', NULL::float; RETURN;
  END IF;

  -- Option 1: nombor pelanggan sedia ada yang pernah disahkan bayar.
  SELECT EXISTS(
    SELECT 1 FROM pesanan_edagang
    WHERE regexp_replace(pelanggan_telefon, '[^0-9]', '', 'g') = v_telefon_rujukan AND status_bayaran = 'disahkan'
  ) INTO v_wujud;

  -- Option 2 (tambahan): nombor didaftar terus oleh pemilik (rujukan_manual, aktif).
  IF NOT v_wujud THEN
    SELECT EXISTS(
      SELECT 1 FROM rujukan_manual
      WHERE regexp_replace(telefon, '[^0-9]', '', 'g') = v_telefon_rujukan AND aktif = true
    ) INTO v_wujud;
  END IF;

  IF NOT v_wujud THEN
    RETURN QUERY SELECT false, 'Kod rujukan tidak dijumpai', NULL::float; RETURN;
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM pesanan_edagang WHERE regexp_replace(pelanggan_telefon, '[^0-9]', '', 'g') = v_telefon_pembeli
  ) INTO v_wujud;
  IF v_wujud THEN
    RETURN QUERY SELECT false, 'Kod rujukan hanya untuk pelanggan baharu (pesanan pertama)', NULL::float; RETURN;
  END IF;

  RETURN QUERY SELECT true, format('Kod rujukan sah — diskaun %s%% untuk pesanan pertama anda!', v_peratus), v_peratus;
END; $$;
