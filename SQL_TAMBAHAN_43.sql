-- SQL_TAMBAHAN_43: Voucher "Percuma Penghantaran" (Free Shipping)
-- Tambah pilihan pada voucher supaya kos penghantaran diwaive sepenuhnya
-- bila kod digunakan. Dikuatkuasakan di SERVER (trigger + validasi_baucar),
-- bukan sekadar client — client hantar kos_penghantaran tetapi trigger
-- akan timpa kepada 0 jika voucher yang digunakan menandakan free shipping.

ALTER TABLE baucar ADD COLUMN IF NOT EXISTS percuma_penghantaran boolean NOT NULL DEFAULT false;

-- validasi_baucar() kini pulangkan juga percuma_penghantaran
DROP FUNCTION IF EXISTS validasi_baucar(text, text, float);

CREATE OR REPLACE FUNCTION validasi_baucar(p_kod text, p_telefon text, p_subjumlah float)
RETURNS TABLE(
  sah boolean, mesej text, diskaun float, jenis_diskaun text, nilai_diskaun float,
  minima_belanja float, maksima_belanja float, tarikh_luput date, had_guna int,
  percuma_penghantaran boolean
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_baucar RECORD; v_diskaun float;
BEGIN
  SELECT * INTO v_baucar FROM baucar WHERE kod = upper(trim(p_kod)) FOR UPDATE;
  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'Kod voucher tidak sah', 0::float, NULL::text, NULL::float, NULL::float, NULL::float, NULL::date, NULL::int, NULL::boolean; RETURN;
  END IF;
  IF NOT v_baucar.aktif THEN
    RETURN QUERY SELECT false, 'Kod voucher tidak aktif', 0::float, NULL::text, NULL::float, v_baucar.minima_belanja, v_baucar.maksima_belanja, v_baucar.tarikh_luput, v_baucar.had_guna, v_baucar.percuma_penghantaran; RETURN;
  END IF;
  IF v_baucar.tarikh_luput IS NOT NULL AND v_baucar.tarikh_luput < CURRENT_DATE THEN
    RETURN QUERY SELECT false, 'Kod voucher telah luput', 0::float, NULL::text, NULL::float, v_baucar.minima_belanja, v_baucar.maksima_belanja, v_baucar.tarikh_luput, v_baucar.had_guna, v_baucar.percuma_penghantaran; RETURN;
  END IF;
  IF p_subjumlah < COALESCE(v_baucar.minima_belanja,0) THEN
    RETURN QUERY SELECT false, format('Perlu belanja minimum RM%s untuk guna kod ini', v_baucar.minima_belanja), 0::float, NULL::text, NULL::float, v_baucar.minima_belanja, v_baucar.maksima_belanja, v_baucar.tarikh_luput, v_baucar.had_guna, v_baucar.percuma_penghantaran; RETURN;
  END IF;
  IF v_baucar.maksima_belanja IS NOT NULL AND p_subjumlah > v_baucar.maksima_belanja THEN
    RETURN QUERY SELECT false, format('Kod ini hanya sah untuk belian sehingga RM%s', v_baucar.maksima_belanja), 0::float, NULL::text, NULL::float, v_baucar.minima_belanja, v_baucar.maksima_belanja, v_baucar.tarikh_luput, v_baucar.had_guna, v_baucar.percuma_penghantaran; RETURN;
  END IF;
  IF v_baucar.had_guna IS NOT NULL AND v_baucar.bilangan_guna >= v_baucar.had_guna THEN
    RETURN QUERY SELECT false, 'Kod voucher telah mencapai had penggunaan', 0::float, NULL::text, NULL::float, v_baucar.minima_belanja, v_baucar.maksima_belanja, v_baucar.tarikh_luput, v_baucar.had_guna, v_baucar.percuma_penghantaran; RETURN;
  END IF;
  IF EXISTS (SELECT 1 FROM baucar_guna WHERE kod = v_baucar.kod AND telefon = p_telefon) THEN
    RETURN QUERY SELECT false, 'Anda sudah guna kod voucher ini sebelum ini', 0::float, NULL::text, NULL::float, v_baucar.minima_belanja, v_baucar.maksima_belanja, v_baucar.tarikh_luput, v_baucar.had_guna, v_baucar.percuma_penghantaran; RETURN;
  END IF;

  v_diskaun := CASE WHEN v_baucar.jenis_diskaun = 'tetap' THEN v_baucar.nilai_diskaun
                     ELSE p_subjumlah * v_baucar.nilai_diskaun / 100 END;
  v_diskaun := LEAST(v_diskaun, p_subjumlah);
  RETURN QUERY SELECT true, 'Kod voucher sah', v_diskaun, v_baucar.jenis_diskaun, v_baucar.nilai_diskaun, v_baucar.minima_belanja, v_baucar.maksima_belanja, v_baucar.tarikh_luput, v_baucar.had_guna, v_baucar.percuma_penghantaran;
END; $$;

-- Trigger pesanan_edagang kini kuatkuasakan percuma_penghantaran di server
-- (timpa kos_penghantaran kepada 0 jika voucher yang sah menandakannya) —
-- client tak boleh "curi" free shipping tanpa kod voucher yang sah.
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

  NEW.jumlah := sub + NEW.kos_penghantaran - COALESCE(NEW.diskaun, 0);
  NEW.status_bayaran := 'menunggu';

  RETURN NEW;
END;
$function$;
