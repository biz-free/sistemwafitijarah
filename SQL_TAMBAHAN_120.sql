-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 120: Diskaun pelanggan affiliate jadi BERSYARAT
-- (minima belian, default RM500, editable setiap affiliate)
--
-- Sebelum ni diskaun pelanggan (kadar_diskaun_peratus) terpakai pada
-- SEBARANG jumlah pesanan asalkan kod affiliate sah. Sekarang diskaun
-- cuma terpakai jika subjumlah pesanan >= minima_belian affiliate itu.
--
-- PENTING: Komisen affiliate (kadar_komisen_peratus) TIDAK terjejas —
-- affiliate tetap dapat komisen atas SEBARANG pesanan yg guna kod dia,
-- tak kira jumlah. Cuma DISKAUN PELANGGAN sahaja jadi bersyarat.
--
-- Kod affiliate kekal SAH walaupun di bawah minima (elak checkout gagal
-- sepenuhnya) — cuma diskaun_peratus dipulangkan sebagai 0 dgn mesej
-- jelas berapa lagi perlu dibelanja.
-- ═══════════════════════════════════════════════════════════

ALTER TABLE affiliates ADD COLUMN IF NOT EXISTS minima_belian numeric DEFAULT 500;

-- validasi_kod_affiliate: tambah parameter p_subjumlah (perlu DROP dulu,
-- CREATE OR REPLACE dgn parameter trailing baharu akan cipta overload
-- kedua, bukan ganti — gotcha yg sama seperti SQL_TAMBAHAN_113/114).
-- Jenis double precision (bukan numeric) supaya padan dgn `sub float`
-- dlm trigger validasi_harga_pesanan_edagang (Postgres tak auto-cast
-- float->numeric utk resolusi overload fungsi).
DROP FUNCTION IF EXISTS public.validasi_kod_affiliate(text, text);
CREATE OR REPLACE FUNCTION public.validasi_kod_affiliate(p_kod_affiliate text, p_telefon_pembeli text, p_subjumlah double precision DEFAULT 0)
 RETURNS TABLE(sah boolean, mesej text, diskaun_peratus double precision, affiliate_id uuid, kadar_komisen_peratus double precision)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_row affiliates%ROWTYPE;
BEGIN
  SELECT * INTO v_row FROM affiliates WHERE kod_affiliate = upper(trim(p_kod_affiliate)) AND status = 'aktif';
  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'Kod affiliate tidak sah atau tidak aktif', NULL::float, NULL::uuid, NULL::float; RETURN;
  END IF;

  IF COALESCE(p_subjumlah, 0) >= COALESCE(v_row.minima_belian, 0) THEN
    RETURN QUERY SELECT true,
      format('Kod affiliate sah — diskaun %s%% untuk pesanan anda!', v_row.kadar_diskaun_peratus),
      v_row.kadar_diskaun_peratus::float, v_row.id, v_row.kadar_komisen_peratus::float;
  ELSE
    RETURN QUERY SELECT true,
      format('Kod affiliate sah! Belanja RM%s lagi untuk dapat diskaun %s%% (minima belian RM%s).',
        ROUND((COALESCE(v_row.minima_belian, 0) - COALESCE(p_subjumlah, 0))::numeric, 2),
        v_row.kadar_diskaun_peratus, v_row.minima_belian),
      0::float, v_row.id, v_row.kadar_komisen_peratus::float;
  END IF;
END;
$function$;

-- validasi_harga_pesanan_edagang: hantar subjumlah sebenar (sub) ke
-- validasi_kod_affiliate supaya semakan minima berlaku di SERVER
-- (bukan setakat client) — sumber kebenaran muktamad.
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
  v_affiliate RECORD;
  v_bil_kod int;
BEGIN
  v_bil_kod := (CASE WHEN NEW.kod_baucar IS NOT NULL AND NEW.kod_baucar <> '' THEN 1 ELSE 0 END)
             + (CASE WHEN NEW.kod_rujukan IS NOT NULL AND NEW.kod_rujukan <> '' THEN 1 ELSE 0 END)
             + (CASE WHEN NEW.kod_affiliate IS NOT NULL AND NEW.kod_affiliate <> '' THEN 1 ELSE 0 END);
  IF v_bil_kod > 1 THEN
    RAISE EXCEPTION 'Hanya satu promosi dibenarkan setiap pesanan — sila guna kod voucher, kod rujukan, ATAU kod affiliate sahaja';
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

  IF NEW.kod_affiliate IS NOT NULL AND NEW.kod_affiliate <> '' THEN
    SELECT * INTO v_affiliate FROM validasi_kod_affiliate(NEW.kod_affiliate, NEW.pelanggan_telefon, sub);
    IF NOT v_affiliate.sah THEN
      RAISE EXCEPTION '%', v_affiliate.mesej;
    END IF;
    NEW.kod_affiliate := upper(trim(NEW.kod_affiliate));
    NEW.affiliate_diskaun := ROUND((sub * v_affiliate.diskaun_peratus / 100)::numeric, 2);
  ELSE
    NEW.affiliate_diskaun := 0;
  END IF;

  NEW.jumlah := sub + NEW.kos_penghantaran - COALESCE(NEW.diskaun, 0) - COALESCE(NEW.rujukan_diskaun, 0) - COALESCE(NEW.affiliate_diskaun, 0);
  NEW.status_bayaran := 'menunggu';

  RETURN NEW;
END;
$function$;

-- lulus_permohonan_affiliate: tambah p_minima_belian
DROP FUNCTION IF EXISTS public.lulus_permohonan_affiliate(uuid, text, numeric, numeric);
CREATE OR REPLACE FUNCTION public.lulus_permohonan_affiliate(p_id uuid, p_kod_affiliate text, p_kadar_komisen numeric, p_kadar_diskaun numeric, p_minima_belian numeric DEFAULT 500)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT is_pemilik() THEN RAISE EXCEPTION 'Hanya pemilik boleh meluluskan permohonan affiliate'; END IF;
  IF trim(COALESCE(p_kod_affiliate,'')) = '' THEN RAISE EXCEPTION 'Kod affiliate diperlukan'; END IF;
  IF p_kadar_komisen < 0 OR p_kadar_komisen > 100 THEN RAISE EXCEPTION 'Kadar komisen tidak sah'; END IF;
  IF p_kadar_diskaun < 0 OR p_kadar_diskaun > 100 THEN RAISE EXCEPTION 'Kadar diskaun tidak sah'; END IF;
  IF p_minima_belian < 0 THEN RAISE EXCEPTION 'Minima belian tidak sah'; END IF;
  UPDATE affiliates SET
    kod_affiliate = upper(trim(p_kod_affiliate)), kadar_komisen_peratus = p_kadar_komisen,
    kadar_diskaun_peratus = p_kadar_diskaun, minima_belian = p_minima_belian, status = 'aktif',
    disahkan_oleh = auth.uid(), disahkan_pada = now()
  WHERE id = p_id AND status = 'menunggu';
  IF NOT FOUND THEN RAISE EXCEPTION 'Permohonan tidak dijumpai atau sudah diproses'; END IF;
END;
$function$;

-- kemaskini_affiliate: tambah p_minima_belian
DROP FUNCTION IF EXISTS public.kemaskini_affiliate(uuid, numeric, numeric, text);
CREATE OR REPLACE FUNCTION public.kemaskini_affiliate(p_id uuid, p_kadar_komisen numeric, p_kadar_diskaun numeric, p_status text, p_minima_belian numeric DEFAULT 500)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT is_pemilik() THEN RAISE EXCEPTION 'Hanya pemilik boleh kemaskini affiliate'; END IF;
  IF p_status NOT IN ('aktif','dinyahaktifkan') THEN RAISE EXCEPTION 'Status tidak sah'; END IF;
  IF p_minima_belian < 0 THEN RAISE EXCEPTION 'Minima belian tidak sah'; END IF;
  UPDATE affiliates SET kadar_komisen_peratus = p_kadar_komisen, kadar_diskaun_peratus = p_kadar_diskaun,
    minima_belian = p_minima_belian, status = p_status
  WHERE id = p_id AND status IN ('aktif','dinyahaktifkan');
  IF NOT FOUND THEN RAISE EXCEPTION 'Affiliate tidak dijumpai'; END IF;
END;
$function$;
