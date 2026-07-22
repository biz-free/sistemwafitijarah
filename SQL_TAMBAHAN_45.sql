-- SQL_TAMBAHAN_45: Kod Referral "Bawa Kawan"
--
-- Setiap pelanggan boleh kongsi NOMBOR TELEFON mereka sendiri sebagai "kod
-- rujukan". Kawan yang buat PESANAN PERTAMA guna kod tu dapat diskaun
-- (default 10%). Bila pesanan kawan tu DISAHKAN bayar, perujuk automatik
-- dapat baucar ganjaran (default RM10, luput 90 hari) — dijana oleh cron
-- rujukan-ganjaran-cron (setiap 15 minit), bukan serta-merta semasa checkout
-- (elak ganjaran diberi untuk pesanan yang akhirnya tak jadi dibayar).

-- Rekod kod rujukan yang digunakan pada setiap pesanan (jika ada).
ALTER TABLE pesanan_edagang ADD COLUMN IF NOT EXISTS kod_rujukan text;
ALTER TABLE pesanan_edagang ADD COLUMN IF NOT EXISTS rujukan_diskaun float NOT NULL DEFAULT 0;

-- Tetapan program rujukan — baris tunggal sama seperti tetapan lain.
ALTER TABLE tetapan ADD COLUMN IF NOT EXISTS rujukan_aktif boolean NOT NULL DEFAULT true;
ALTER TABLE tetapan ADD COLUMN IF NOT EXISTS rujukan_diskaun_kawan_peratus float NOT NULL DEFAULT 10;
ALTER TABLE tetapan ADD COLUMN IF NOT EXISTS rujukan_ganjaran_rm float NOT NULL DEFAULT 10;
ALTER TABLE tetapan ADD COLUMN IF NOT EXISTS rujukan_luput_hari int NOT NULL DEFAULT 90;

-- Log setiap ganjaran rujukan yang dijana — UNIQUE(pesanan_id) jadi penanda
-- "pesanan ni dah diproses", elak ganjaran berganda untuk pesanan yang sama.
CREATE TABLE IF NOT EXISTS rujukan_ganjaran (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  pesanan_id text NOT NULL UNIQUE REFERENCES pesanan_edagang(id) ON DELETE CASCADE,
  telefon_perujuk text NOT NULL,
  telefon_kawan text NOT NULL,
  kod_ganjaran text NOT NULL,
  nilai_ganjaran float NOT NULL,
  emel_dihantar boolean NOT NULL DEFAULT false,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_rujukan_ganjaran_perujuk ON rujukan_ganjaran(telefon_perujuk);

ALTER TABLE rujukan_ganjaran ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "pemilik baca rujukan_ganjaran" ON rujukan_ganjaran;
CREATE POLICY "pemilik baca rujukan_ganjaran" ON rujukan_ganjaran FOR SELECT USING (is_pemilik());
-- Tiada policy INSERT untuk client — hanya Edge Function (service_role) yang tulis.

-- Sahkan kod rujukan (dipanggil dari index.html semasa checkout, dan dari
-- trigger validasi_harga_pesanan_edagang semasa pesanan sebenar dihantar).
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

  SELECT EXISTS(
    SELECT 1 FROM pesanan_edagang
    WHERE regexp_replace(pelanggan_telefon, '[^0-9]', '', 'g') = v_telefon_rujukan AND status_bayaran = 'disahkan'
  ) INTO v_wujud;
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

-- Kemaskini trigger sedia ada supaya turut sahkan & kira diskaun rujukan di
-- SERVER (bukan client) — sama pattern macam kod_baucar.
CREATE OR REPLACE FUNCTION validasi_harga_pesanan_edagang()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
  item jsonb;
  item_baru jsonb := '[]'::jsonb;
  harga_sebenar float;
  sub float := 0;
  kos_min float := 0;
  v_check RECORD;
  v_rujukan RECORD;
BEGIN
  FOR item IN SELECT * FROM jsonb_array_elements(COALESCE(NEW.items, '[]'::jsonb)) LOOP
    SELECT harga_jual INTO harga_sebenar FROM stok WHERE id = item->>'stokId';
    IF harga_sebenar IS NULL THEN
      RAISE EXCEPTION 'Produk % tidak wujud atau telah dipadam', item->>'stokId';
    END IF;
    item_baru := item_baru || jsonb_build_object(
      'stokId', item->>'stokId',
      'nama', item->>'nama',
      'unit', item->>'unit',
      'harga', harga_sebenar,
      'qty', (item->>'qty')::int
    );
    sub := sub + harga_sebenar * (item->>'qty')::int;
  END LOOP;

  NEW.items := item_baru;
  NEW.subjumlah := sub;

  SELECT MIN(kadar_asas) INTO kos_min FROM zon_penghantaran;
  IF NEW.kos_penghantaran IS NULL OR NEW.kos_penghantaran < COALESCE(kos_min, 0) THEN
    NEW.kos_penghantaran := COALESCE(kos_min, 0);
  END IF;

  IF NEW.kod_baucar IS NOT NULL AND NEW.kod_baucar <> '' THEN
    SELECT * INTO v_check FROM validasi_baucar(NEW.kod_baucar, NEW.pelanggan_telefon, sub);
    IF NOT v_check.sah THEN
      RAISE EXCEPTION '%', v_check.mesej;
    END IF;
    NEW.diskaun := v_check.diskaun;
    NEW.kod_baucar := upper(trim(NEW.kod_baucar));
    IF v_check.percuma_penghantaran THEN
      NEW.kos_penghantaran := 0;
    END IF;
    UPDATE baucar SET bilangan_guna = bilangan_guna + 1 WHERE kod = NEW.kod_baucar;
    INSERT INTO baucar_guna (kod, telefon, pesanan_id) VALUES (NEW.kod_baucar, NEW.pelanggan_telefon, NEW.id);
  ELSE
    NEW.diskaun := 0;
  END IF;

  IF NEW.kod_rujukan IS NOT NULL AND NEW.kod_rujukan <> '' THEN
    SELECT * INTO v_rujukan FROM validasi_rujukan(NEW.kod_rujukan, NEW.pelanggan_telefon);
    IF NOT v_rujukan.sah THEN
      RAISE EXCEPTION '%', v_rujukan.mesej;
    END IF;
    NEW.rujukan_diskaun := ROUND((sub * v_rujukan.diskaun_peratus / 100)::numeric, 2);
  ELSE
    NEW.rujukan_diskaun := 0;
  END IF;

  NEW.jumlah := sub + NEW.kos_penghantaran - COALESCE(NEW.diskaun, 0) - COALESCE(NEW.rujukan_diskaun, 0);
  NEW.status_bayaran := 'menunggu';

  RETURN NEW;
END;
$function$;
