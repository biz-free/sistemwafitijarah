-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 111: Sistem Affiliate (akaun khas, log masuk Google)
-- ═══════════════════════════════════════════════════════════
-- Beza drpd "Kod Rujukan Bawa Kawan" sedia ada (kod_rujukan/rujukan_ganjaran,
-- ikut NOMBOR TELEFON semata-mata, tiada akaun/log masuk):
--   • Affiliate ada AKAUN SEBENAR (Google OAuth via Supabase Auth) + papan pemuka
--     sendiri (affiliate.html) — bukan sekadar lookup nombor telefon.
--   • Komisen dikira utk SETIAP pesanan disahkan (bukan sekadar pesanan pertama).
--   • Perlu permohonan awam + kelulusan pemilik dahulu sebelum kod aktif.
--   • Bayaran melalui permohonan/kelulusan (transfer bank manual), bukan baucar
--     diskaun automatik.
--
-- Sengaja jadual BERASINGAN drpd `profiles` (bukan tambah role='affiliate' di
-- situ) — elak sebarang risiko kepada logik currentRole pekerja/pemilik sedia
-- ada di pengurusan.html yg sudah luas bergantung kpd 2 role tu sahaja.
--
-- Kekangan direka bentuk (jawapan pemilik semasa perbincangan):
--   1. Pelanggan dapat diskaun (kadar_diskaun_peratus) + affiliate dapat komisen
--      (kadar_komisen_peratus) drpd jumlah SEBELUM diskaun — kedua boleh beza
--      setiap affiliate, ditetapkan pemilik semasa lulus permohonan.
--   2. Permohonan AWAM (borang di index.html, log masuk Google dahulu) → status
--      'menunggu' → pemilik lulus/tolak.
--   3. Bayaran komisen = transfer bank MANUAL (sistem rekod sahaja, spt Baucar
--      Bayaran/Bayar Hutang sedia ada) — bukan gateway automatik.
--   4. Kod affiliate SATU SLOT sahaja di checkout — tak boleh gabung dgn kod
--      voucher/rujukan sedia ada (kekal margin terkawal, elak diskaun bertindan).
-- ═══════════════════════════════════════════════════════════

-- ── Jadual akaun affiliate (1 baris = 1 permohonan/akaun, id = auth.uid()) ──
CREATE TABLE affiliates (
  id uuid PRIMARY KEY REFERENCES auth.users(id),
  nama text NOT NULL,
  telefon text NOT NULL,
  cara_promosi text,
  kod_affiliate text UNIQUE,                    -- ditetapkan pemilik semasa lulus (NULL semasa menunggu)
  kadar_komisen_peratus numeric NOT NULL DEFAULT 10,
  kadar_diskaun_peratus numeric NOT NULL DEFAULT 5,
  nama_bank text,
  no_akaun_bank text,
  pemegang_akaun text,
  status text NOT NULL DEFAULT 'menunggu' CHECK (status IN ('menunggu','aktif','ditolak','dinyahaktifkan')),
  sebab_tolak text,
  disahkan_oleh uuid REFERENCES auth.users(id),
  disahkan_pada timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE affiliates ENABLE ROW LEVEL SECURITY;

-- Affiliate lihat rekod sendiri sahaja; pemilik lihat semua.
CREATE POLICY "affiliate lihat sendiri, pemilik lihat semua" ON affiliates FOR SELECT
  USING (id = auth.uid() OR is_pemilik());
-- HANYA pemilik boleh UPDATE terus (kelulusan/kadar/status) — affiliate TAK boleh
-- ubah kadar_komisen/status sendiri. Kemaskini butiran bank affiliate diarah
-- melalui RPC SECURITY DEFINER (kemaskini_bank_affiliate) supaya terhad kpd
-- medan bank sahaja, elak affiliate escalate kadar/status sendiri.
CREATE POLICY "pemilik urus semua affiliate" ON affiliates FOR UPDATE
  USING (is_pemilik());
-- Permohonan awam: pengguna Google-authenticated insert rekod SENDIRI sahaja.
CREATE POLICY "pengguna mohon jadi affiliate sendiri" ON affiliates FOR INSERT
  WITH CHECK (id = auth.uid());

-- ── Ledger komisen — 1 baris = 1 pesanan e-dagang disahkan yg guna kod affiliate ──
CREATE TABLE affiliate_earnings (
  id text PRIMARY KEY,
  affiliate_id uuid REFERENCES affiliates(id) NOT NULL,
  pesanan_id text REFERENCES pesanan_edagang(id) NOT NULL UNIQUE,
  jumlah_pesanan numeric NOT NULL,             -- subjumlah pesanan (sblm diskaun/penghantaran)
  kadar_komisen_peratus numeric NOT NULL,      -- snapshot kadar semasa pesanan disahkan
  jumlah_komisen numeric NOT NULL,
  status text NOT NULL DEFAULT 'tertunggak' CHECK (status IN ('tertunggak','boleh_tuntut','dibayar','dibatalkan')),
  tarikh_boleh_tuntut date NOT NULL,
  payout_id text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_affiliate_earnings_affiliate ON affiliate_earnings(affiliate_id);

ALTER TABLE affiliate_earnings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "affiliate lihat pendapatan sendiri, pemilik lihat semua" ON affiliate_earnings FOR SELECT
  USING (affiliate_id = auth.uid() OR is_pemilik());

-- ── Permohonan bayaran komisen (transfer bank manual, dua-fasa spt Bayar Hutang) ──
CREATE TABLE affiliate_payout (
  id text PRIMARY KEY,
  affiliate_id uuid REFERENCES affiliates(id) NOT NULL,
  jumlah numeric NOT NULL CHECK (jumlah > 0),
  status text NOT NULL DEFAULT 'menunggu' CHECK (status IN ('menunggu','dibayar','ditolak')),
  nota text,
  created_at timestamptz NOT NULL DEFAULT now(),
  disahkan_oleh uuid REFERENCES auth.users(id),
  disahkan_pada timestamptz
);

ALTER TABLE affiliate_payout ENABLE ROW LEVEL SECURITY;
CREATE POLICY "affiliate lihat & mohon bayaran sendiri, pemilik lihat semua" ON affiliate_payout FOR SELECT
  USING (affiliate_id = auth.uid() OR is_pemilik());

-- ── Lanjutan pesanan_edagang: sokongan kod affiliate (sama corak kod_baucar/kod_rujukan) ──
ALTER TABLE pesanan_edagang ADD COLUMN kod_affiliate text;
ALTER TABLE pesanan_edagang ADD COLUMN affiliate_diskaun double precision NOT NULL DEFAULT 0;

-- ── Validasi kod affiliate (sama pattern spt validasi_baucar/validasi_rujukan) ──
CREATE OR REPLACE FUNCTION public.validasi_kod_affiliate(p_kod_affiliate text, p_telefon_pembeli text)
RETURNS TABLE(sah boolean, mesej text, diskaun_peratus double precision, affiliate_id uuid, kadar_komisen_peratus double precision)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_row affiliates%ROWTYPE;
BEGIN
  SELECT * INTO v_row FROM affiliates WHERE kod_affiliate = upper(trim(p_kod_affiliate)) AND status = 'aktif';
  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'Kod affiliate tidak sah atau tidak aktif', NULL::float, NULL::uuid, NULL::float; RETURN;
  END IF;
  RETURN QUERY SELECT true,
    format('Kod affiliate sah — diskaun %s%% untuk pesanan anda!', v_row.kadar_diskaun_peratus),
    v_row.kadar_diskaun_peratus::float, v_row.id, v_row.kadar_komisen_peratus::float;
END; $$;
GRANT EXECUTE ON FUNCTION public.validasi_kod_affiliate(text, text) TO anon, authenticated;

-- ── Kemaskini trigger harga pesanan e-dagang: tambah cabang ke-3 (affiliate),
-- kekalkan sepenuhnya logik voucher/rujukan sedia ada, cuma perluas semakan
-- "satu promosi sahaja" drpd 2-hala ke 3-hala. ──
CREATE OR REPLACE FUNCTION public.validasi_harga_pesanan_edagang()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public' AS $function$
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
    SELECT * INTO v_affiliate FROM validasi_kod_affiliate(NEW.kod_affiliate, NEW.pelanggan_telefon);
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

-- ── Cipta pendapatan affiliate sebaik pesanan DISAHKAN bayar (bukan cron —
-- terus via trigger supaya affiliate nampak komisen serta-merta, elak lengah
-- spt cron rujukan 15 minit). Tempoh tahan 14 hari sblm "boleh_tuntut" (lindung
-- drpd pembatalan/refund lewat). ──
CREATE OR REPLACE FUNCTION public.cipta_pendapatan_affiliate()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_kadar numeric;
BEGIN
  IF NEW.status_bayaran = 'disahkan' AND OLD.status_bayaran IS DISTINCT FROM 'disahkan'
     AND NEW.kod_affiliate IS NOT NULL AND NEW.kod_affiliate <> '' THEN
    SELECT kadar_komisen_peratus INTO v_kadar FROM affiliates WHERE kod_affiliate = NEW.kod_affiliate AND status = 'aktif';
    IF v_kadar IS NOT NULL THEN
      INSERT INTO affiliate_earnings (id, affiliate_id, pesanan_id, jumlah_pesanan, kadar_komisen_peratus, jumlah_komisen, tarikh_boleh_tuntut)
      SELECT gen_random_uuid()::text, a.id, NEW.id, NEW.subjumlah, v_kadar, ROUND((NEW.subjumlah * v_kadar / 100)::numeric, 2), (CURRENT_DATE + INTERVAL '14 days')::date
      FROM affiliates a WHERE a.kod_affiliate = NEW.kod_affiliate AND a.status = 'aktif'
      ON CONFLICT (pesanan_id) DO NOTHING;
    END IF;
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_cipta_pendapatan_affiliate ON pesanan_edagang;
CREATE TRIGGER trg_cipta_pendapatan_affiliate
  AFTER UPDATE ON pesanan_edagang
  FOR EACH ROW EXECUTE FUNCTION cipta_pendapatan_affiliate();

-- ── Matangkan pendapatan tertunggak -> boleh_tuntut selepas tempoh tahan.
-- Dipanggil harian via pg_cron (dijadualkan di bawah). ──
CREATE OR REPLACE FUNCTION public.matangkan_pendapatan_affiliate()
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  UPDATE affiliate_earnings SET status = 'boleh_tuntut'
  WHERE status = 'tertunggak' AND tarikh_boleh_tuntut <= CURRENT_DATE;
$$;
GRANT EXECUTE ON FUNCTION public.matangkan_pendapatan_affiliate() TO service_role;

SELECT cron.schedule('matangkan-pendapatan-affiliate-harian', '0 17 * * *', $$SELECT public.matangkan_pendapatan_affiliate();$$);

-- ── RPC: mohon jadi affiliate (pengguna Google-authenticated, borang awam) ──
CREATE OR REPLACE FUNCTION public.mohon_jadi_affiliate(p_nama text, p_telefon text, p_cara_promosi text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Log masuk Google diperlukan'; END IF;
  IF trim(COALESCE(p_nama,'')) = '' THEN RAISE EXCEPTION 'Nama diperlukan'; END IF;
  IF trim(COALESCE(p_telefon,'')) = '' THEN RAISE EXCEPTION 'No. telefon diperlukan'; END IF;
  IF EXISTS (SELECT 1 FROM affiliates WHERE id = auth.uid()) THEN
    RAISE EXCEPTION 'Anda sudah pernah memohon — semak status permohonan anda';
  END IF;
  INSERT INTO affiliates (id, nama, telefon, cara_promosi)
  VALUES (auth.uid(), trim(p_nama), trim(p_telefon), p_cara_promosi);
END; $$;
GRANT EXECUTE ON FUNCTION public.mohon_jadi_affiliate(text, text, text) TO authenticated;

-- ── RPC: pemilik lulus permohonan (tetapkan kod + kadar) ──
CREATE OR REPLACE FUNCTION public.lulus_permohonan_affiliate(p_id uuid, p_kod_affiliate text, p_kadar_komisen numeric, p_kadar_diskaun numeric)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_pemilik() THEN RAISE EXCEPTION 'Hanya pemilik boleh meluluskan permohonan affiliate'; END IF;
  IF trim(COALESCE(p_kod_affiliate,'')) = '' THEN RAISE EXCEPTION 'Kod affiliate diperlukan'; END IF;
  IF p_kadar_komisen < 0 OR p_kadar_komisen > 100 THEN RAISE EXCEPTION 'Kadar komisen tidak sah'; END IF;
  IF p_kadar_diskaun < 0 OR p_kadar_diskaun > 100 THEN RAISE EXCEPTION 'Kadar diskaun tidak sah'; END IF;
  UPDATE affiliates SET
    kod_affiliate = upper(trim(p_kod_affiliate)), kadar_komisen_peratus = p_kadar_komisen,
    kadar_diskaun_peratus = p_kadar_diskaun, status = 'aktif',
    disahkan_oleh = auth.uid(), disahkan_pada = now()
  WHERE id = p_id AND status = 'menunggu';
  IF NOT FOUND THEN RAISE EXCEPTION 'Permohonan tidak dijumpai atau sudah diproses'; END IF;
END; $$;
GRANT EXECUTE ON FUNCTION public.lulus_permohonan_affiliate(uuid, text, numeric, numeric) TO authenticated;

-- ── RPC: pemilik tolak permohonan ──
CREATE OR REPLACE FUNCTION public.tolak_permohonan_affiliate(p_id uuid, p_sebab text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_pemilik() THEN RAISE EXCEPTION 'Hanya pemilik boleh menolak permohonan affiliate'; END IF;
  UPDATE affiliates SET status = 'ditolak', sebab_tolak = p_sebab, disahkan_oleh = auth.uid(), disahkan_pada = now()
  WHERE id = p_id AND status = 'menunggu';
  IF NOT FOUND THEN RAISE EXCEPTION 'Permohonan tidak dijumpai atau sudah diproses'; END IF;
END; $$;
GRANT EXECUTE ON FUNCTION public.tolak_permohonan_affiliate(uuid, text) TO authenticated;

-- ── RPC: pemilik nyahaktif/aktifkan semula affiliate & ubah kadar ──
CREATE OR REPLACE FUNCTION public.kemaskini_affiliate(p_id uuid, p_kadar_komisen numeric, p_kadar_diskaun numeric, p_status text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_pemilik() THEN RAISE EXCEPTION 'Hanya pemilik boleh kemaskini affiliate'; END IF;
  IF p_status NOT IN ('aktif','dinyahaktifkan') THEN RAISE EXCEPTION 'Status tidak sah'; END IF;
  UPDATE affiliates SET kadar_komisen_peratus = p_kadar_komisen, kadar_diskaun_peratus = p_kadar_diskaun, status = p_status
  WHERE id = p_id AND status IN ('aktif','dinyahaktifkan');
  IF NOT FOUND THEN RAISE EXCEPTION 'Affiliate tidak dijumpai'; END IF;
END; $$;
GRANT EXECUTE ON FUNCTION public.kemaskini_affiliate(uuid, numeric, numeric, text) TO authenticated;

-- ── RPC: affiliate kemaskini butiran bank sendiri (medan terhad, elak escalate) ──
CREATE OR REPLACE FUNCTION public.kemaskini_bank_affiliate(p_nama_bank text, p_no_akaun text, p_pemegang text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Log masuk diperlukan'; END IF;
  UPDATE affiliates SET nama_bank = p_nama_bank, no_akaun_bank = p_no_akaun, pemegang_akaun = p_pemegang
  WHERE id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'Akaun affiliate tidak dijumpai'; END IF;
END; $$;
GRANT EXECUTE ON FUNCTION public.kemaskini_bank_affiliate(text, text, text) TO authenticated;

-- ── RPC: affiliate mohon bayaran (had kpd baki 'boleh_tuntut' blm dipohon) ──
CREATE OR REPLACE FUNCTION public.mohon_bayaran_affiliate(p_jumlah numeric)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_baki numeric; v_id text; v_status text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Log masuk diperlukan'; END IF;
  SELECT status INTO v_status FROM affiliates WHERE id = auth.uid();
  IF v_status IS DISTINCT FROM 'aktif' THEN RAISE EXCEPTION 'Akaun affiliate anda tidak aktif'; END IF;
  SELECT COALESCE(SUM(jumlah_komisen), 0) INTO v_baki FROM affiliate_earnings
    WHERE affiliate_id = auth.uid() AND status = 'boleh_tuntut';
  IF p_jumlah <= 0 OR p_jumlah > v_baki THEN
    RAISE EXCEPTION 'Jumlah permohonan melebihi baki boleh tuntut (RM%)', round(v_baki, 2);
  END IF;
  IF EXISTS (SELECT 1 FROM affiliate_payout WHERE affiliate_id = auth.uid() AND status = 'menunggu') THEN
    RAISE EXCEPTION 'Anda sudah ada permohonan bayaran menunggu — tunggu keputusan dahulu';
  END IF;
  v_id := 'PO' || substr(replace(gen_random_uuid()::text,'-',''),1,8);
  INSERT INTO affiliate_payout (id, affiliate_id, jumlah) VALUES (v_id, auth.uid(), p_jumlah);
  -- Tandakan earnings yg dimasukkan dlm permohonan ni (elak dituntut dua kali) —
  -- ambil earnings TERLAMA dahulu (FIFO) sehingga cukup jumlah dipohon.
  UPDATE affiliate_earnings SET payout_id = v_id
  WHERE id IN (
    SELECT id FROM affiliate_earnings WHERE affiliate_id = auth.uid() AND status = 'boleh_tuntut' AND payout_id IS NULL
    ORDER BY created_at
  );
END; $$;
GRANT EXECUTE ON FUNCTION public.mohon_bayaran_affiliate(numeric) TO authenticated;

-- ── RPC: pemilik sahkan bayaran (transfer sudah dibuat di luar sistem) ──
CREATE OR REPLACE FUNCTION public.sahkan_bayaran_affiliate(p_id text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_pemilik() THEN RAISE EXCEPTION 'Hanya pemilik boleh sahkan bayaran affiliate'; END IF;
  UPDATE affiliate_payout SET status = 'dibayar', disahkan_oleh = auth.uid(), disahkan_pada = now()
  WHERE id = p_id AND status = 'menunggu';
  IF NOT FOUND THEN RAISE EXCEPTION 'Permohonan tidak dijumpai atau sudah diproses'; END IF;
  UPDATE affiliate_earnings SET status = 'dibayar' WHERE payout_id = p_id;
END; $$;
GRANT EXECUTE ON FUNCTION public.sahkan_bayaran_affiliate(text) TO authenticated;

-- ── RPC: pemilik tolak permohonan bayaran (lepaskan earnings semula) ──
CREATE OR REPLACE FUNCTION public.tolak_bayaran_affiliate(p_id text, p_sebab text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_pemilik() THEN RAISE EXCEPTION 'Hanya pemilik boleh tolak permohonan bayaran affiliate'; END IF;
  UPDATE affiliate_payout SET status = 'ditolak', nota = p_sebab, disahkan_oleh = auth.uid(), disahkan_pada = now()
  WHERE id = p_id AND status = 'menunggu';
  IF NOT FOUND THEN RAISE EXCEPTION 'Permohonan tidak dijumpai atau sudah diproses'; END IF;
  UPDATE affiliate_earnings SET payout_id = NULL WHERE payout_id = p_id;
END; $$;
GRANT EXECUTE ON FUNCTION public.tolak_bayaran_affiliate(text, text) TO authenticated;

-- ── RPC: papan pemuka affiliate (ringkasan) ──
CREATE OR REPLACE FUNCTION public.dashboard_affiliate_saya()
RETURNS TABLE(tertunggak numeric, boleh_tuntut numeric, dibayar numeric, jumlah_pesanan bigint)
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT
    COALESCE(SUM(jumlah_komisen) FILTER (WHERE status = 'tertunggak'), 0),
    COALESCE(SUM(jumlah_komisen) FILTER (WHERE status = 'boleh_tuntut'), 0),
    COALESCE(SUM(jumlah_komisen) FILTER (WHERE status = 'dibayar'), 0),
    COUNT(*)
  FROM affiliate_earnings WHERE affiliate_id = auth.uid();
$$;
GRANT EXECUTE ON FUNCTION public.dashboard_affiliate_saya() TO authenticated;
