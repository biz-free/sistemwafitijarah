-- ═══════════════════════════════════════════════════════════
--  WAFI TIJARAH TRADING — SQL TAMBAHAN #29
--  Jalankan SEKALI sahaja dalam Supabase SQL Editor.
--  (Voucher Diskaun untuk storefront B2C index.html — pemilik generate
--   kod voucher (peratus/tetap, minima belanja, had guna keseluruhan,
--   tarikh luput), pelanggan masukkan kod semasa checkout. Sekali guna
--   sahaja setiap nombor telefon. Client hanya hantar kod — server yang
--   sahkan & kira diskaun sebenar secara atomik dalam trigger sedia ada.)
-- ═══════════════════════════════════════════════════════════

ALTER TABLE baucar ADD COLUMN IF NOT EXISTS had_guna int; -- null = tiada had
ALTER TABLE baucar ADD COLUMN IF NOT EXISTS bilangan_guna int NOT NULL DEFAULT 0;
ALTER TABLE pesanan_edagang ADD COLUMN IF NOT EXISTS kod_baucar text;

CREATE TABLE IF NOT EXISTS baucar_guna (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kod text NOT NULL REFERENCES baucar(kod),
  telefon text NOT NULL,
  pesanan_id text REFERENCES pesanan_edagang(id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
  created_at timestamptz DEFAULT now(),
  UNIQUE(kod, telefon)
);
ALTER TABLE baucar_guna ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "pemilik baca baucar_guna" ON baucar_guna;
CREATE POLICY "pemilik baca baucar_guna" ON baucar_guna FOR SELECT USING (is_pemilik());

-- Fungsi validasi kongsi — dipanggil dari RPC preview checkout DAN dari trigger
-- penciptaan pesanan (guna FOR UPDATE supaya selamat bila 2 pesanan serentak
-- guna kod voucher berhad).
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
END;
$$;
GRANT EXECUTE ON FUNCTION validasi_baucar(text, text, float) TO anon, authenticated;

-- Kemaskini trigger penciptaan pesanan_edagang: sahkan & kira diskaun voucher
-- (jika ada) secara atomik dengan penciptaan pesanan, kemudian rekod penggunaan.
CREATE OR REPLACE FUNCTION validasi_harga_pesanan_edagang()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  item jsonb;
  item_baru jsonb := '[]'::jsonb;
  harga_sebenar float;
  sub float := 0;
  kos_min float := 0;
  v_check RECORD;
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
    UPDATE baucar SET bilangan_guna = bilangan_guna + 1 WHERE kod = NEW.kod_baucar;
    INSERT INTO baucar_guna (kod, telefon, pesanan_id) VALUES (NEW.kod_baucar, NEW.pelanggan_telefon, NEW.id);
  ELSE
    NEW.diskaun := 0;
  END IF;

  NEW.jumlah := sub + NEW.kos_penghantaran - COALESCE(NEW.diskaun, 0);
  NEW.status_bayaran := 'menunggu';

  RETURN NEW;
END;
$$;
