-- SQL_TAMBAHAN_50: Voucher & Kod Rujukan Saling Eksklusif (Elak Double Claim)
--
-- index.html (client) sudah digugurkan salah satu kod bila pembeli cuba guna
-- kedua-duanya sekali gus. Tambah SATU LAGI lapisan pengesahan di
-- validasi_harga_pesanan_edagang() (trigger BEFORE INSERT pesanan_edagang)
-- supaya tolakan berlaku di server juga — elak permintaan API terus
-- (bypass UI) daripada guna voucher + kod rujukan serentak dalam satu pesanan.

CREATE OR REPLACE FUNCTION public.validasi_harga_pesanan_edagang()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  item jsonb;
  item_baru jsonb := '[]'::jsonb;
  harga_sebenar float;
  sub float := 0;
  kos_min float := 0;
  v_check RECORD;
  v_rujukan RECORD;
BEGIN
  IF NEW.kod_baucar IS NOT NULL AND NEW.kod_baucar <> '' AND NEW.kod_rujukan IS NOT NULL AND NEW.kod_rujukan <> '' THEN
    RAISE EXCEPTION 'Hanya satu promosi dibenarkan setiap pesanan — sila guna sama ada kod voucher ATAU kod rujukan, bukan kedua-duanya';
  END IF;

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
