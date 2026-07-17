-- ═══════════════════════════════════════════════════════════
--  WAFI TIJARAH TRADING — SQL SETUP LENGKAP (versi terkini, semua ciri)
--  Jalankan SEKALI sahaja dalam Supabase SQL Editor pada project BAHARU.
--  (Jika project sedia ada dah guna versi lama, jangan run fail ini —
--   guna SQL_TAMBAHAN_2/3/4/5.sql secara berturutan sebaliknya.)
-- ═══════════════════════════════════════════════════════════

-- ═══ Jadual data ═══
CREATE TABLE stok (
  id text PRIMARY KEY,
  nama text NOT NULL,
  unit text DEFAULT 'unit',
  harga_beli float DEFAULT 0,
  harga_jual float DEFAULT 0,
  stok int DEFAULT 0,
  kategori text DEFAULT 'Minuman',
  tarikh_luput date,
  gambar_url text,
  berat float DEFAULT 0.5,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE kedai (
  id text PRIMARY KEY,
  nama text NOT NULL,
  alamat text,
  negeri text,
  daerah text,
  telefon text,
  lat float DEFAULT 5.15,
  lng float DEFAULT 100.85,
  status text DEFAULT 'aktif',
  hutang float DEFAULT 0,
  nota text,
  last_visit text,
  didaftarkan_oleh uuid REFERENCES auth.users(id),
  gambar_urls jsonb DEFAULT '[]',
  created_at timestamptz DEFAULT now()
);

CREATE TABLE transaksi (
  id text PRIMARY KEY,
  tarikh_masa timestamptz DEFAULT now(),
  kedai_id text REFERENCES kedai(id),
  nama_pembeli text,
  items jsonb DEFAULT '[]',
  jumlah float DEFAULT 0,
  jumlah_asal float,
  diskaun_peratus float DEFAULT 0,
  kaedah_bayaran text DEFAULT 'tunai',
  status text DEFAULT 'selesai',
  nota text,
  resit text,
  jarak_km float DEFAULT 0,
  created_by text,
  items_terjual jsonb, -- kuantiti sebenar terjual (consignment) — [{stokId, qty}]
  jualan_disahkan boolean NOT NULL DEFAULT true, -- consignment bermula false sehingga jualan disahkan
  disahkan_oleh uuid REFERENCES auth.users(id),
  disahkan_pada timestamptz
);

-- Profil pekerja/pemilik — dipautkan ke akaun Supabase Auth
CREATE TABLE profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email text,
  role text NOT NULL DEFAULT 'pekerja',
  nama text,
  telefon text,
  must_change_password boolean DEFAULT false,
  webauthn_credential_id text
);

-- Pesanan masuk dari kedai melalui link/QR awam pesan.html (repeat order)
CREATE TABLE pre_order (
  id text PRIMARY KEY,
  kedai_id text REFERENCES kedai(id),
  kedai_nama text NOT NULL,
  kedai_telefon text,
  items jsonb DEFAULT '[]',
  nota text,
  status text DEFAULT 'baru', -- baru / diproses / selesai
  assigned_pekerja_id uuid REFERENCES auth.users(id),
  bayar_metod text DEFAULT 'cod', -- cod / transfer
  jumlah_asal float DEFAULT 0,
  diskaun_peratus float DEFAULT 0,
  jumlah_selepas_diskaun float DEFAULT 0,
  bayar_tarikh date,
  bayar_masa text,
  bukti_bayaran_url text,
  created_at timestamptz DEFAULT now()
);

-- Kehadiran (Thumb In/Out) & jejak GPS untuk claim minyak
CREATE TABLE kehadiran (
  id text PRIMARY KEY,
  pekerja_id uuid REFERENCES auth.users(id),
  thumb_in_masa timestamptz,
  thumb_in_lat float,
  thumb_in_lng float,
  thumb_out_masa timestamptz,
  thumb_out_lat float,
  thumb_out_lng float,
  status text DEFAULT 'aktif',
  gps_device_id text,
  gps_last_ping timestamptz,
  created_at timestamptz DEFAULT now()
);
CREATE TABLE gps_track (
  id bigserial PRIMARY KEY,
  kehadiran_id text REFERENCES kehadiran(id) ON DELETE CASCADE,
  pekerja_id uuid REFERENCES auth.users(id),
  lat float,
  lng float,
  tarikh_masa timestamptz DEFAULT now()
);

-- Stok bawaan pekerja (diambil dari gudang sebelum bergerak ke kedai)
CREATE TABLE stok_pekerja (
  id bigserial PRIMARY KEY,
  pekerja_id uuid REFERENCES auth.users(id),
  stok_id text REFERENCES stok(id),
  kuantiti int DEFAULT 0,
  UNIQUE(pekerja_id, stok_id)
);

-- Permohonan Cuti / MC / Off
CREATE TABLE permohonan_cuti (
  id text PRIMARY KEY,
  pekerja_id uuid REFERENCES auth.users(id),
  jenis text NOT NULL, -- cuti / mc / off
  tarikh_mula date NOT NULL,
  tarikh_tamat date NOT NULL,
  nota text,
  status text DEFAULT 'menunggu', -- menunggu / diluluskan / ditolak
  created_at timestamptz DEFAULT now()
);

-- Tetapan Pre-Order & Diskaun Online Transfer (1 baris, boleh baca umum)
CREATE TABLE tetapan (
  id int PRIMARY KEY DEFAULT 1,
  minima_transfer float DEFAULT 500,
  diskaun_peratus float DEFAULT 5,
  qr_bank_url text,
  butiran_bank text,
  pengirim_nama text DEFAULT 'Wafi Tijarah Trading',
  pengirim_telefon text,
  pengirim_email text,
  pengirim_alamat text,
  pengirim_poskod text,
  pengirim_bandar text,
  pengirim_negeri text,
  CONSTRAINT satu_baris_sahaja CHECK (id = 1)
);
INSERT INTO tetapan (id) VALUES (1);

-- ═══ Row Level Security ═══
ALTER TABLE stok ENABLE ROW LEVEL SECURITY;
ALTER TABLE kedai ENABLE ROW LEVEL SECURITY;
ALTER TABLE transaksi ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE pre_order ENABLE ROW LEVEL SECURITY;
ALTER TABLE kehadiran ENABLE ROW LEVEL SECURITY;
ALTER TABLE gps_track ENABLE ROW LEVEL SECURITY;
ALTER TABLE stok_pekerja ENABLE ROW LEVEL SECURITY;
ALTER TABLE permohonan_cuti ENABLE ROW LEVEL SECURITY;
ALTER TABLE tetapan ENABLE ROW LEVEL SECURITY;

-- Fungsi SECURITY DEFINER supaya semakan peranan pemilik TIDAK query terus
-- profiles dari dalam dasar profiles sendiri (elak "infinite recursion").
CREATE OR REPLACE FUNCTION is_pemilik() RETURNS boolean
LANGUAGE sql SECURITY DEFINER SET search_path = public STABLE AS $$
  SELECT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'pemilik');
$$;

CREATE POLICY "profil sendiri" ON profiles FOR SELECT USING (auth.uid() = id);
CREATE POLICY "pemilik boleh baca semua profil" ON profiles FOR SELECT USING (is_pemilik());
CREATE POLICY "pemilik boleh daftar profil pekerja" ON profiles FOR INSERT WITH CHECK (is_pemilik());

CREATE POLICY "baca stok" ON stok FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "baca kedai" ON kedai FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "baca transaksi" ON transaksi FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "pemilik tambah stok" ON stok FOR INSERT WITH CHECK (
  EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'pemilik')
);
CREATE POLICY "pemilik kemaskini stok" ON stok FOR UPDATE USING (
  EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'pemilik')
);
-- Kedai: pemilik ATAU pekerja boleh daftar kedai baru (pekerja cari prospek di lapangan)
CREATE POLICY "staff tambah kedai" ON kedai FOR INSERT WITH CHECK (auth.role() = 'authenticated');
CREATE POLICY "pemilik kemaskini kedai" ON kedai FOR UPDATE USING (
  EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'pemilik')
);

-- Pre-order: sesiapa (tanpa log masuk) boleh hantar; pekerja nampak yang belum
-- ditugaskan atau ditugaskan kepada diri sendiri sahaja; pemilik nampak semua.
CREATE POLICY "sesiapa boleh hantar pre-order" ON pre_order FOR INSERT WITH CHECK (true);
CREATE POLICY "staff boleh baca pre-order" ON pre_order FOR SELECT USING (
  is_pemilik() OR assigned_pekerja_id IS NULL OR assigned_pekerja_id = auth.uid()
);
CREATE POLICY "staff boleh kemaskini pre-order" ON pre_order FOR UPDATE USING (auth.role() = 'authenticated');

-- KESELAMATAN: sama sebab seperti pesanan_edagang di atas — RLS insert
-- sengaja terbuka untuk borang awam pesan.html, jadi trigger ini kira
-- semula jumlah daripada stok sebenar & tetapan diskaun/consignment
-- sedia ada, abaikan apa client hantar.
CREATE OR REPLACE FUNCTION validasi_harga_pre_order()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  item jsonb;
  harga_item float;
  sub float := 0;
  t_minima float; t_diskaun float; t_diskaun_cod float; t_had_consignment float;
  peratus float := 0;
BEGIN
  FOR item IN SELECT * FROM jsonb_array_elements(COALESCE(NEW.items, '[]'::jsonb)) LOOP
    SELECT harga_jual INTO harga_item FROM stok WHERE id = item->>'stokId';
    IF harga_item IS NULL THEN
      RAISE EXCEPTION 'Produk % tidak wujud atau telah dipadam', item->>'stokId';
    END IF;
    sub := sub + harga_item * (item->>'qty')::int;
  END LOOP;

  SELECT minima_transfer, diskaun_peratus, diskaun_cod_peratus, consignment_limit
    INTO t_minima, t_diskaun, t_diskaun_cod, t_had_consignment
    FROM tetapan WHERE id = 1;

  IF NEW.bayar_metod = 'consignment' AND sub >= COALESCE(t_had_consignment, 300) THEN
    NEW.bayar_metod := 'cod';
  END IF;

  IF sub >= COALESCE(t_minima, 500) THEN
    IF NEW.bayar_metod = 'cod' THEN peratus := COALESCE(t_diskaun_cod, 0);
    ELSIF NEW.bayar_metod = 'transfer' THEN peratus := COALESCE(t_diskaun, 0);
    END IF;
  END IF;

  NEW.jumlah_asal := sub;
  NEW.diskaun_peratus := peratus;
  NEW.jumlah_selepas_diskaun := sub * (1 - peratus/100);
  NEW.status := 'baru';

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validasi_harga_pre_order ON pre_order;
CREATE TRIGGER trg_validasi_harga_pre_order
  BEFORE INSERT ON pre_order
  FOR EACH ROW EXECUTE FUNCTION validasi_harga_pre_order();

CREATE POLICY "pekerja urus kehadiran sendiri" ON kehadiran FOR ALL USING (pekerja_id = auth.uid()) WITH CHECK (pekerja_id = auth.uid());
CREATE POLICY "pemilik baca semua kehadiran" ON kehadiran FOR SELECT USING (is_pemilik());
CREATE POLICY "pekerja tambah gps sendiri" ON gps_track FOR INSERT WITH CHECK (pekerja_id = auth.uid());
CREATE POLICY "pekerja baca gps sendiri" ON gps_track FOR SELECT USING (pekerja_id = auth.uid());
CREATE POLICY "pemilik baca semua gps" ON gps_track FOR SELECT USING (is_pemilik());

CREATE POLICY "pekerja baca stok bawaan sendiri" ON stok_pekerja FOR SELECT USING (pekerja_id = auth.uid() OR is_pemilik());

CREATE POLICY "pekerja urus permohonan sendiri" ON permohonan_cuti FOR ALL USING (pekerja_id = auth.uid()) WITH CHECK (pekerja_id = auth.uid());
CREATE POLICY "pemilik baca semua permohonan" ON permohonan_cuti FOR SELECT USING (is_pemilik());
CREATE POLICY "pemilik kelulusan permohonan" ON permohonan_cuti FOR UPDATE USING (is_pemilik());

CREATE POLICY "semua boleh baca tetapan" ON tetapan FOR SELECT USING (true);
CREATE POLICY "pemilik boleh kemaskini tetapan" ON tetapan FOR UPDATE USING (is_pemilik());

-- ═══ Fungsi RPC — kemaskini stok bawaan/hutang secara atomik ═══
CREATE OR REPLACE FUNCTION submit_penghantaran(
  p_id text, p_kedai_id text, p_items jsonb, p_jumlah float,
  p_status text, p_nota text, p_resit text, p_jarak_km float DEFAULT 0
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE item jsonb;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid()) THEN
    RAISE EXCEPTION 'Tidak dibenarkan';
  END IF;

  -- Potong dari stok BAWAAN pekerja (bukan gudang terus) — gudang dah ditolak
  -- semasa pekerja "ambil stok" sebelum bergerak ke kedai.
  FOR item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    UPDATE stok_pekerja SET kuantiti = kuantiti - (item->>'qty')::int
      WHERE pekerja_id = auth.uid() AND stok_id = item->>'stokId' AND kuantiti >= (item->>'qty')::int;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Stok bawaan anda tidak mencukupi untuk %', item->>'stokId';
    END IF;
  END LOOP;

  INSERT INTO transaksi (id, kedai_id, items, jumlah, status, nota, resit, jarak_km, created_by)
  VALUES (p_id, p_kedai_id, p_items, p_jumlah, p_status, p_nota, p_resit, p_jarak_km, auth.uid()::text);

  UPDATE kedai SET
    hutang = hutang + (CASE WHEN p_status = 'hutang' THEN p_jumlah ELSE 0 END),
    last_visit = CURRENT_DATE::text
  WHERE id = p_kedai_id;
END;
$$;

CREATE OR REPLACE FUNCTION restock_produk(p_id text, p_qty int) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'pemilik') THEN
    RAISE EXCEPTION 'Hanya pemilik boleh restock';
  END IF;
  UPDATE stok SET stok = stok + p_qty WHERE id = p_id;
END;
$$;

CREATE OR REPLACE FUNCTION rekod_bayaran(p_kedai_id text, p_jumlah float) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE baki float := p_jumlah; t RECORD;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'pemilik') THEN
    RAISE EXCEPTION 'Hanya pemilik boleh rekod bayaran';
  END IF;
  UPDATE kedai SET hutang = GREATEST(0, hutang - p_jumlah) WHERE id = p_kedai_id;
  FOR t IN
    SELECT id, jumlah FROM transaksi
    WHERE kedai_id = p_kedai_id AND status = 'hutang'
    ORDER BY tarikh_masa ASC
  LOOP
    EXIT WHEN baki < t.jumlah;
    UPDATE transaksi SET status = 'selesai' WHERE id = t.id;
    baki := baki - t.jumlah;
  END LOOP;
END;
$$;

-- Pekerja ambil stok dari gudang (self-service, tiada kelulusan)
CREATE OR REPLACE FUNCTION ambil_stok_pekerja(p_stok_id text, p_qty int) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_qty <= 0 THEN RAISE EXCEPTION 'Kuantiti mesti lebih 0'; END IF;
  UPDATE stok SET stok = stok - p_qty WHERE id = p_stok_id AND stok >= p_qty;
  IF NOT FOUND THEN RAISE EXCEPTION 'Stok gudang tidak mencukupi'; END IF;
  INSERT INTO stok_pekerja (pekerja_id, stok_id, kuantiti) VALUES (auth.uid(), p_stok_id, p_qty)
    ON CONFLICT (pekerja_id, stok_id) DO UPDATE SET kuantiti = stok_pekerja.kuantiti + p_qty;
END;
$$;
GRANT EXECUTE ON FUNCTION ambil_stok_pekerja(text, int) TO authenticated;

-- Pekerja pulangkan stok bawaan balik ke gudang
CREATE OR REPLACE FUNCTION pulang_stok_pekerja(p_stok_id text, p_qty int) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_qty <= 0 THEN RAISE EXCEPTION 'Kuantiti mesti lebih 0'; END IF;
  UPDATE stok_pekerja SET kuantiti = kuantiti - p_qty WHERE pekerja_id = auth.uid() AND stok_id = p_stok_id AND kuantiti >= p_qty;
  IF NOT FOUND THEN RAISE EXCEPTION 'Stok bawaan anda tidak mencukupi'; END IF;
  UPDATE stok SET stok = stok + p_qty WHERE id = p_stok_id;
END;
$$;
GRANT EXECUTE ON FUNCTION pulang_stok_pekerja(text, int) TO authenticated;

-- Padam transaksi kedai (pemilik sahaja) — pulangkan stok yang telah ditolak semasa
-- penghantaran asal ke stok gudang pusat, dan laraskan balik hutang kedai jika berkaitan.
CREATE OR REPLACE FUNCTION padam_transaksi_kedai(p_id text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_trx RECORD; item jsonb;
BEGIN
  IF NOT is_pemilik() THEN RAISE EXCEPTION 'Hanya pemilik boleh padam transaksi'; END IF;

  SELECT * INTO v_trx FROM transaksi WHERE id = p_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Transaksi tidak dijumpai'; END IF;

  FOR item IN SELECT * FROM jsonb_array_elements(v_trx.items) LOOP
    UPDATE stok SET stok = stok + (item->>'qty')::int WHERE id = item->>'stokId';
  END LOOP;

  IF v_trx.status = 'hutang' AND v_trx.kedai_id IS NOT NULL THEN
    UPDATE kedai SET hutang = GREATEST(0, hutang - v_trx.jumlah) WHERE id = v_trx.kedai_id;
  END IF;

  DELETE FROM transaksi WHERE id = p_id;
END;
$$;
GRANT EXECUTE ON FUNCTION padam_transaksi_kedai(text) TO authenticated;

-- Kemaskini profil sendiri (nama/telefon sahaja — tak dedah medan role)
CREATE OR REPLACE FUNCTION kemaskini_profil_sendiri(p_nama text, p_telefon text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE profiles SET nama = p_nama, telefon = p_telefon WHERE id = auth.uid();
END;
$$;
GRANT EXECUTE ON FUNCTION kemaskini_profil_sendiri(text, text) TO authenticated;

-- ═══ Fungsi awam — senarai produk (tanpa harga beli/modal) untuk borang pre-order ═══
CREATE OR REPLACE FUNCTION senarai_produk_awam()
RETURNS TABLE(id text, nama text, unit text, harga_jual float, kategori text, gambar_url text)
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT id, nama, unit, harga_jual, kategori, gambar_url FROM stok ORDER BY nama;
$$;
GRANT EXECUTE ON FUNCTION senarai_produk_awam() TO anon, authenticated;

-- ═══ Fungsi awam — maklumat asas kedai (untuk prefill borang bila dibuka via QR resit) ═══
CREATE OR REPLACE FUNCTION maklumat_kedai_awam(p_id text)
RETURNS TABLE(nama text, telefon text)
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT nama, telefon FROM kedai WHERE id = p_id;
$$;
GRANT EXECUTE ON FUNCTION maklumat_kedai_awam(text) TO anon, authenticated;

-- ═══ Profil pemilik (akaun anda: biz.amirul@gmail.com) ═══
INSERT INTO profiles (id, email, role, nama) VALUES
  ('7c2af1ae-3808-4e9d-a878-c22c2717e90d', 'biz.amirul@gmail.com', 'pemilik', 'Amirul');

-- ═══ Seed produk asal (boleh edit/buang lepas ini dalam apps) ═══
INSERT INTO stok (id, nama, unit, harga_beli, harga_jual, stok, kategori) VALUES
  ('S001','Tamar Cocoa 900g','kotak',20.00,26.00,50,'Minuman'),
  ('S002','Tamar Cocoa Beg','beg',18.50,24.00,60,'Minuman'),
  ('S003','Tamar Cocoa Papan','papan',18.50,24.00,40,'Minuman'),
  ('S004','Tamar Cocoa 450g','kotak',12.50,17.00,55,'Minuman'),
  ('S005','Tamar Coffee Bag','beg',21.00,27.50,45,'Minuman'),
  ('S006','T.T.Tarik (Bag)','beg',18.00,23.50,50,'Minuman'),
  ('S007','Natural Hair Cream','unit',9.00,14.00,30,'Kesihatan & Kecantikan'),
  ('S008','K.A.K.F. Manjakani','unit',18.00,25.00,25,'Kesihatan & Kecantikan'),
  ('S009','K.A.T.A. Ginseng (Kotak)','kotak',18.50,25.00,30,'Kesihatan & Kecantikan'),
  ('S010','K. Arabica Tanpa Gula','beg',12.00,17.00,40,'Minuman'),
  ('S011','Goat Milk Classic','unit',25.00,33.00,20,'Minuman'),
  ('S012','T. Green Tea Latte (Beg)','beg',22.00,28.50,35,'Minuman');

-- ═══════════════════════════════════════════════════════════
--  STORAGE BUCKETS — cipta dahulu melalui Dashboard (SQL tak boleh cipta bucket):
--    1. Storage → New bucket → nama: produk-gambar → Public bucket: ON
--    2. Storage → New bucket → nama: bukti-bayaran → Public bucket: OFF (data sensitif)
--  Lepas KEDUA-DUA bucket wujud, jalankan dasar akses di bawah:
-- ═══════════════════════════════════════════════════════════
CREATE POLICY "awam boleh lihat gambar produk" ON storage.objects FOR SELECT USING (bucket_id = 'produk-gambar');
CREATE POLICY "pemilik boleh upload gambar produk" ON storage.objects FOR INSERT WITH CHECK (bucket_id = 'produk-gambar' AND is_pemilik());
CREATE POLICY "pemilik boleh kemaskini gambar produk" ON storage.objects FOR UPDATE USING (bucket_id = 'produk-gambar' AND is_pemilik());
CREATE POLICY "pemilik boleh padam gambar produk" ON storage.objects FOR DELETE USING (bucket_id = 'produk-gambar' AND is_pemilik());

CREATE POLICY "sesiapa boleh upload bukti bayaran" ON storage.objects FOR INSERT WITH CHECK (bucket_id = 'bukti-bayaran');
CREATE POLICY "staff boleh lihat bukti bayaran" ON storage.objects FOR SELECT USING (bucket_id = 'bukti-bayaran' AND auth.role() = 'authenticated');

-- 3. Storage → New bucket → nama: kedai-gambar → Public bucket: ON (galeri gambar depan kedai)
CREATE POLICY "awam boleh lihat gambar kedai" ON storage.objects FOR SELECT USING (bucket_id = 'kedai-gambar');
CREATE POLICY "staff boleh upload gambar kedai" ON storage.objects FOR INSERT WITH CHECK (bucket_id = 'kedai-gambar' AND auth.role() = 'authenticated');
CREATE POLICY "staff boleh padam gambar kedai" ON storage.objects FOR DELETE USING (bucket_id = 'kedai-gambar' AND auth.role() = 'authenticated');

-- 4. Storage → New bucket → nama: baucar-resit → Public bucket: OFF (resit baucar bayaran, data kewangan)
CREATE POLICY "staff boleh upload resit baucar" ON storage.objects FOR INSERT WITH CHECK (bucket_id = 'baucar-resit' AND auth.role() = 'authenticated');
CREATE POLICY "staff boleh lihat resit baucar" ON storage.objects FOR SELECT USING (bucket_id = 'baucar-resit' AND auth.role() = 'authenticated');

-- ═══ Hantar permohonan cuti & claim pre-order — atomik guna auth.uid() server-side ═══
CREATE OR REPLACE FUNCTION hantar_permohonan_cuti(
  p_id text, p_jenis text, p_mula date, p_tamat date, p_nota text
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid()) THEN
    RAISE EXCEPTION 'Tidak dibenarkan';
  END IF;
  INSERT INTO permohonan_cuti (id, pekerja_id, jenis, tarikh_mula, tarikh_tamat, nota, status)
  VALUES (p_id, auth.uid(), p_jenis, p_mula, p_tamat, p_nota, 'menunggu');
END;
$$;
GRANT EXECUTE ON FUNCTION hantar_permohonan_cuti(text,text,date,date,text) TO authenticated;

CREATE OR REPLACE FUNCTION claim_preorder(p_id text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid()) THEN
    RAISE EXCEPTION 'Tidak dibenarkan';
  END IF;
  UPDATE pre_order SET assigned_pekerja_id = auth.uid()
    WHERE id = p_id AND assigned_pekerja_id IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pre-order ini sudah diambil oleh pekerja lain (atau tidak wujud)';
  END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION claim_preorder(text) TO authenticated;
-- ═══════════════════════════════════════════════════════════
--  WAFI TIJARAH TRADING — SQL TAMBAHAN #7
--  Jalankan SEKALI sahaja dalam Supabase SQL Editor.
--  (Tempoh tugasan, delete data, gambar berbilang, consignment,
--   tugaskan pekerja, dashboard notifikasi/status live)
-- ═══════════════════════════════════════════════════════════

-- ═══ Pre-Order: tempoh tugasan (auto-lepas jika lepas 1 hari) ═══
ALTER TABLE pre_order ADD COLUMN IF NOT EXISTS claimed_at timestamptz;

-- Lepaskan (unclaim) tugasan yang diambil tapi tak selesai melepasi hari yang sama
-- — dipanggil setiap kali senarai pre-order dimuat, supaya automatik pulang ke kumpulan.
CREATE OR REPLACE FUNCTION lepaskan_preorder_lapuk() RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE pre_order SET assigned_pekerja_id = NULL, claimed_at = NULL
  WHERE assigned_pekerja_id IS NOT NULL
    AND status != 'selesai'
    AND claimed_at::date < CURRENT_DATE;
END;
$$;
GRANT EXECUTE ON FUNCTION lepaskan_preorder_lapuk() TO authenticated, anon;

-- Kemaskini claim_preorder supaya rekod claimed_at sekali
CREATE OR REPLACE FUNCTION claim_preorder(p_id text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid()) THEN
    RAISE EXCEPTION 'Tidak dibenarkan';
  END IF;
  UPDATE pre_order SET assigned_pekerja_id = auth.uid(), claimed_at = now()
    WHERE id = p_id AND assigned_pekerja_id IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pre-order ini sudah diambil oleh pekerja lain (atau tidak wujud)';
  END IF;
END;
$$;

-- Pemilik boleh tugaskan/ubah tugasan pekerja terus (bukan sekadar pekerja claim sendiri)
CREATE OR REPLACE FUNCTION tugaskan_preorder(p_id text, p_pekerja_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'pemilik') THEN
    RAISE EXCEPTION 'Hanya pemilik boleh tugaskan pekerja';
  END IF;
  UPDATE pre_order SET assigned_pekerja_id = p_pekerja_id, claimed_at = CASE WHEN p_pekerja_id IS NULL THEN NULL ELSE now() END
  WHERE id = p_id;
END;
$$;
GRANT EXECUTE ON FUNCTION tugaskan_preorder(text, uuid) TO authenticated;

-- ═══ Consignment (kedai letak barang dulu, bayar lepas jual) — nilai bayar_metod baharu ═══
-- (medan bayar_metod dah wujud sebagai text bebas, tiada perubahan skema diperlukan;
--  'consignment' cuma satu lagi nilai yang sah, dikawal di sisi aplikasi)

-- ═══ Gambar produk berbilang (galeri) ═══
ALTER TABLE stok ADD COLUMN IF NOT EXISTS gambar_urls jsonb DEFAULT '[]';

DROP FUNCTION IF EXISTS senarai_produk_awam();
CREATE FUNCTION senarai_produk_awam()
RETURNS TABLE(id text, nama text, unit text, harga_jual float, kategori text, gambar_url text, gambar_urls jsonb, jumlah_terjual bigint, berat float)
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT s.id, s.nama, s.unit, s.harga_jual, s.kategori, s.gambar_url, s.gambar_urls,
    COALESCE((SELECT SUM((item->>'qty')::int) FROM transaksi t, jsonb_array_elements(t.items) item WHERE item->>'stokId' = s.id), 0) AS jumlah_terjual,
    s.berat
  FROM stok s ORDER BY nama;
$$;
GRANT EXECUTE ON FUNCTION senarai_produk_awam() TO anon, authenticated;

-- ═══ Padam data (pemilik sahaja) ═══
DROP POLICY IF EXISTS "pemilik padam stok" ON stok;
CREATE POLICY "pemilik padam stok" ON stok FOR DELETE USING (is_pemilik());
DROP POLICY IF EXISTS "pemilik padam kedai" ON kedai;
CREATE POLICY "pemilik padam kedai" ON kedai FOR DELETE USING (is_pemilik());
DROP POLICY IF EXISTS "pemilik padam transaksi" ON transaksi;
CREATE POLICY "pemilik padam transaksi" ON transaksi FOR DELETE USING (is_pemilik());
DROP POLICY IF EXISTS "pemilik padam pre_order" ON pre_order;
CREATE POLICY "pemilik padam pre_order" ON pre_order FOR DELETE USING (is_pemilik());
DROP POLICY IF EXISTS "pemilik padam kehadiran" ON kehadiran;
CREATE POLICY "pemilik padam kehadiran" ON kehadiran FOR DELETE USING (is_pemilik());
DROP POLICY IF EXISTS "pemilik padam permohonan_cuti" ON permohonan_cuti;
CREATE POLICY "pemilik padam permohonan_cuti" ON permohonan_cuti FOR DELETE USING (is_pemilik());
DROP POLICY IF EXISTS "pemilik padam stok_pekerja" ON stok_pekerja;
CREATE POLICY "pemilik padam stok_pekerja" ON stok_pekerja FOR DELETE USING (is_pemilik());

-- ═══ Notifikasi ringkas — kiraan siap (tiada jadual baharu, kira terus dari data sedia ada) ═══
-- Pemilik: bilangan permohonan cuti "menunggu" + pre-order "baru"
-- Pekerja: bilangan pre-order "baru" yang belum ditugaskan
-- (Dikira terus di client bila diperlukan — tiada perubahan skema untuk ini)
-- (Gambar berbilang & jumlah_terjual sudah termasuk dalam senarai_produk_awam versi ini)

-- ═══ Alamat & lokasi GPS pre-order (pembeli cari lokasi kedai sendiri di borang awam) ═══
ALTER TABLE pre_order ADD COLUMN IF NOT EXISTS alamat text;
ALTER TABLE pre_order ADD COLUMN IF NOT EXISTS lat float8;
ALTER TABLE pre_order ADD COLUMN IF NOT EXISTS lng float8;

-- ═══ Rekod Baru: Belian Peribadi (tiada kedai destinasi) ═══
ALTER TABLE transaksi ADD COLUMN IF NOT EXISTS nama_pembeli text;

-- ═══ Rekod Baru: Kaedah Bayaran (Tunai/Online Transfer/Hutang) & diskaun % ═══
ALTER TABLE transaksi ADD COLUMN IF NOT EXISTS kaedah_bayaran text DEFAULT 'tunai';
ALTER TABLE transaksi ADD COLUMN IF NOT EXISTS jumlah_asal float;
ALTER TABLE transaksi ADD COLUMN IF NOT EXISTS diskaun_peratus float DEFAULT 0;

CREATE OR REPLACE FUNCTION submit_penghantaran(
  p_id text, p_kedai_id text, p_items jsonb, p_jumlah float,
  p_status text, p_nota text, p_resit text, p_jarak_km float DEFAULT 0,
  p_nama_pembeli text DEFAULT NULL,
  p_kaedah_bayaran text DEFAULT 'tunai', p_jumlah_asal float DEFAULT NULL, p_diskaun_peratus float DEFAULT 0
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE item jsonb;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid()) THEN
    RAISE EXCEPTION 'Tidak dibenarkan';
  END IF;

  FOR item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    UPDATE stok_pekerja SET kuantiti = kuantiti - (item->>'qty')::int
      WHERE pekerja_id = auth.uid() AND stok_id = item->>'stokId' AND kuantiti >= (item->>'qty')::int;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Stok bawaan anda tidak mencukupi untuk %', item->>'stokId';
    END IF;
  END LOOP;

  INSERT INTO transaksi (id, kedai_id, nama_pembeli, items, jumlah, status, nota, resit, jarak_km, created_by, kaedah_bayaran, jumlah_asal, diskaun_peratus, jualan_disahkan)
  VALUES (p_id, p_kedai_id, p_nama_pembeli, p_items, p_jumlah, p_status, p_nota, p_resit, p_jarak_km, auth.uid()::text, p_kaedah_bayaran, COALESCE(p_jumlah_asal, p_jumlah), p_diskaun_peratus, (p_kaedah_bayaran <> 'consignment'));

  UPDATE kedai SET
    hutang = hutang + (CASE WHEN p_status = 'hutang' THEN p_jumlah ELSE 0 END),
    last_visit = CURRENT_DATE::text
  WHERE id = p_kedai_id;
END;
$$;

-- ═══ Upah pekerja per-produk (gantikan kadar sejagat) ═══
ALTER TABLE stok ADD COLUMN IF NOT EXISTS upah_pekerja float DEFAULT 0;

-- ═══ Status pekerja aktif/tidak aktif (pekerja tidak aktif boleh dipadam) ═══
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'aktif';

DROP POLICY IF EXISTS "pemilik padam profil pekerja" ON profiles;
CREATE POLICY "pemilik padam profil pekerja" ON profiles FOR DELETE USING (is_pemilik());

-- ═══ Baiki: padam kedai gagal (409) jika ada sejarah transaksi/pre-order ═══
ALTER TABLE transaksi DROP CONSTRAINT IF EXISTS transaksi_kedai_id_fkey;
ALTER TABLE transaksi ADD CONSTRAINT transaksi_kedai_id_fkey
  FOREIGN KEY (kedai_id) REFERENCES kedai(id) ON DELETE SET NULL;

ALTER TABLE pre_order DROP CONSTRAINT IF EXISTS pre_order_kedai_id_fkey;
ALTER TABLE pre_order ADD CONSTRAINT pre_order_kedai_id_fkey
  FOREIGN KEY (kedai_id) REFERENCES kedai(id) ON DELETE SET NULL;

-- ═══ Diskaun dua peringkat: COD/Tunai + Online Transfer, & had Consignment (RM) ═══
ALTER TABLE tetapan ADD COLUMN IF NOT EXISTS diskaun_cod_peratus float DEFAULT 5;
ALTER TABLE tetapan ADD COLUMN IF NOT EXISTS consignment_limit float DEFAULT 300;

-- ═══ Minima pesanan untuk penghantaran percuma (pesan.html) ═══
ALTER TABLE tetapan ADD COLUMN IF NOT EXISTS minima_penghantaran_percuma float DEFAULT 100;

-- ═══ Permohonan Ejen & Penghantar Part-Time (pesan.html) ═══
CREATE TABLE IF NOT EXISTS pemohon_program (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  jenis text NOT NULL CHECK (jenis IN ('ejen','penghantar','marketing')),
  nama text NOT NULL,
  telefon text NOT NULL,
  kawasan text,
  ada_kenderaan boolean,
  nota text,
  nama_produk text, -- servis marketing sahaja
  harga float, -- servis marketing sahaja
  margin_peratus float, -- servis marketing sahaja
  gambar_url text, -- servis marketing sahaja
  status text DEFAULT 'baru',
  created_at timestamptz DEFAULT now()
);
ALTER TABLE pemohon_program ENABLE ROW LEVEL SECURITY;
CREATE POLICY "sesiapa boleh mohon" ON pemohon_program FOR INSERT WITH CHECK (true);
CREATE POLICY "staff boleh baca permohonan" ON pemohon_program FOR SELECT
  USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid()));
CREATE POLICY "staff boleh kemaskini permohonan" ON pemohon_program FOR UPDATE
  USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid()));
CREATE POLICY "pemilik boleh padam permohonan" ON pemohon_program FOR DELETE USING (is_pemilik());

-- ═══ Fasa 1 Laman E-Dagang (index.html): zon penghantaran & pesanan e-dagang ═══
CREATE TABLE IF NOT EXISTS zon_penghantaran (
  id text PRIMARY KEY,
  nama text NOT NULL,
  kadar_asas float DEFAULT 0,
  kadar_per_kg float DEFAULT 0,
  anggaran_hari text
);

ALTER TABLE zon_penghantaran ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "semua boleh baca zon" ON zon_penghantaran;
CREATE POLICY "semua boleh baca zon" ON zon_penghantaran FOR SELECT USING (true);
DROP POLICY IF EXISTS "pemilik urus zon" ON zon_penghantaran;
CREATE POLICY "pemilik urus zon" ON zon_penghantaran FOR ALL USING (is_pemilik());

INSERT INTO zon_penghantaran (id, nama, kadar_asas, kadar_per_kg, anggaran_hari) VALUES
  ('semenanjung', 'Semenanjung Malaysia', 6, 1.5, '2-4 hari bekerja'),
  ('sabah_sarawak', 'Sabah & Sarawak', 12, 3, '4-7 hari bekerja')
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS pesanan_edagang (
  id text PRIMARY KEY,
  auth_uid uuid REFERENCES auth.users(id),
  pelanggan_nama text NOT NULL,
  pelanggan_telefon text NOT NULL,
  pelanggan_email text,
  items jsonb DEFAULT '[]',
  subjumlah float DEFAULT 0,
  kos_penghantaran float DEFAULT 0,
  diskaun float DEFAULT 0,
  kod_baucar text,
  jumlah float DEFAULT 0,
  alamat text,
  poskod text,
  bandar text,
  negeri text,
  zon_penghantaran text REFERENCES zon_penghantaran(id),
  nama_kurier text,
  no_tracking text,
  kurier_service_id text,
  easyparcel_status text,
  easyparcel_awb_url text,
  easyparcel_tracking_url text,
  billplz_bill_id text,
  kaedah_bayaran text DEFAULT 'transfer',
  status_bayaran text DEFAULT 'menunggu',
  status_pesanan text DEFAULT 'baru',
  bukti_bayaran_url text,
  bayar_tarikh date,
  bayar_masa time,
  nota text,
  assigned_pekerja_id uuid REFERENCES auth.users(id),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE pesanan_edagang ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "sesiapa boleh buat pesanan" ON pesanan_edagang;
CREATE POLICY "sesiapa boleh buat pesanan" ON pesanan_edagang FOR INSERT WITH CHECK (true);
DROP POLICY IF EXISTS "staff boleh baca pesanan" ON pesanan_edagang;
DROP POLICY IF EXISTS "staff boleh baca semua pesanan" ON pesanan_edagang;
-- Pemilik nampak semua pesanan; pekerja hanya nampak pesanan yang DITUGASKAN kepada
-- mereka — jika pemilik tak pilih pekerja itu, pekerja tak nampak pesanan langsung.
CREATE POLICY "pemilik baca semua pesanan edagang" ON pesanan_edagang FOR SELECT USING (is_pemilik());
CREATE POLICY "pekerja baca pesanan edagang ditugaskan" ON pesanan_edagang FOR SELECT USING (assigned_pekerja_id = auth.uid());
DROP POLICY IF EXISTS "pelanggan boleh baca pesanan sendiri" ON pesanan_edagang;
CREATE POLICY "pelanggan boleh baca pesanan sendiri" ON pesanan_edagang FOR SELECT
  USING (auth.uid() IS NOT NULL AND auth.uid() = auth_uid);
DROP POLICY IF EXISTS "staff boleh kemaskini pesanan" ON pesanan_edagang;
CREATE POLICY "pemilik kemaskini semua pesanan edagang" ON pesanan_edagang FOR UPDATE USING (is_pemilik());
CREATE POLICY "pekerja kemaskini pesanan edagang ditugaskan" ON pesanan_edagang FOR UPDATE
  USING (assigned_pekerja_id = auth.uid()) WITH CHECK (assigned_pekerja_id = auth.uid());
DROP POLICY IF EXISTS "pemilik boleh padam pesanan" ON pesanan_edagang;
CREATE POLICY "pemilik boleh padam pesanan" ON pesanan_edagang FOR DELETE USING (is_pemilik());

-- KESELAMATAN: RLS insert di atas sengaja WITH CHECK(true) supaya guest checkout
-- boleh insert — tapi ini bermakna client boleh hantar harga/status_bayaran apa
-- sahaja terus melalui REST API. Trigger ini kira SEMULA harga setiap item
-- daripada `stok` sebenar dan paksa status_bayaran='menunggu' pada penciptaan,
-- tanpa mengira apa client hantar.
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

DROP TRIGGER IF EXISTS trg_validasi_harga_pesanan_edagang ON pesanan_edagang;
CREATE TRIGGER trg_validasi_harga_pesanan_edagang
  BEFORE INSERT ON pesanan_edagang
  FOR EACH ROW EXECUTE FUNCTION validasi_harga_pesanan_edagang();

CREATE TABLE IF NOT EXISTS alamat_pelanggan (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_uid uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  label text DEFAULT 'Rumah',
  nama_penerima text,
  telefon text,
  alamat text NOT NULL,
  poskod text,
  negeri text,
  utama boolean DEFAULT false,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE alamat_pelanggan ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "pelanggan urus alamat sendiri" ON alamat_pelanggan;
CREATE POLICY "pelanggan urus alamat sendiri" ON alamat_pelanggan FOR ALL
  USING (auth.uid() = auth_uid) WITH CHECK (auth.uid() = auth_uid);

CREATE TABLE IF NOT EXISTS baucar (
  kod text PRIMARY KEY,
  jenis_diskaun text DEFAULT 'peratus',
  nilai_diskaun float DEFAULT 0,
  minima_belanja float DEFAULT 0,
  tarikh_luput date,
  aktif boolean DEFAULT true,
  had_guna int, -- null = tiada had
  bilangan_guna int NOT NULL DEFAULT 0
);

ALTER TABLE baucar ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "semua boleh baca baucar aktif" ON baucar;
CREATE POLICY "semua boleh baca baucar aktif" ON baucar FOR SELECT USING (aktif = true);
DROP POLICY IF EXISTS "pemilik urus baucar" ON baucar;
CREATE POLICY "pemilik urus baucar" ON baucar FOR ALL USING (is_pemilik());

-- Penjejakan penggunaan voucher setiap pelanggan (sekali guna sahaja setiap no. telefon)
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

-- ═══ Fasa 3a — Sambungan OAuth EasyParcel (lihat PANDUAN_SETUP.md untuk deploy Edge Function) ═══
CREATE TABLE IF NOT EXISTS easyparcel_auth (
  id int PRIMARY KEY DEFAULT 1,
  access_token text,
  refresh_token text,
  expires_at timestamptz,
  connected_at timestamptz,
  CONSTRAINT easyparcel_auth_single_row CHECK (id = 1)
);
INSERT INTO easyparcel_auth (id) VALUES (1) ON CONFLICT (id) DO NOTHING;
ALTER TABLE easyparcel_auth ENABLE ROW LEVEL SECURITY;
-- (Sengaja tiada CREATE POLICY — jadual tertutup dari client, hanya Edge Function/service_role boleh akses.)

CREATE OR REPLACE FUNCTION easyparcel_status()
RETURNS TABLE(connected boolean, connected_at timestamptz, expires_at timestamptz)
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT (access_token IS NOT NULL), connected_at, expires_at FROM easyparcel_auth WHERE id = 1;
$$;
GRANT EXECUTE ON FUNCTION easyparcel_status() TO authenticated;

-- ═══ Fungsi awam — semak status bayaran pesanan (guest checkout Billplz guna ini
--     selepas redirect balik; sengaja tak pulangkan alamat/telefon/emel) ═══
CREATE OR REPLACE FUNCTION semak_status_pesanan(p_id text)
RETURNS TABLE(status_bayaran text, status_pesanan text, jumlah float)
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT status_bayaran, status_pesanan, jumlah FROM pesanan_edagang WHERE id = p_id;
$$;
GRANT EXECUTE ON FUNCTION semak_status_pesanan(text) TO anon, authenticated;

-- ═══ Pelupusan Stok — pekerja rekod stok bawaan rosak/expired/hilang dari tab Penghantaran ═══
CREATE TABLE IF NOT EXISTS pelupusan_stok (
  id text PRIMARY KEY,
  pekerja_id uuid REFERENCES auth.users(id),
  stok_id text REFERENCES stok(id),
  kuantiti int NOT NULL,
  sebab text NOT NULL DEFAULT 'rosak', -- rosak / expired / hilang / lain
  nota text,
  kos float DEFAULT 0, -- anggaran kerugian (harga_beli × kuantiti masa itu, kekal walau harga_beli berubah kemudian)
  created_at timestamptz DEFAULT now()
);
ALTER TABLE pelupusan_stok ENABLE ROW LEVEL SECURITY;
CREATE POLICY "pekerja urus pelupusan sendiri" ON pelupusan_stok FOR ALL USING (pekerja_id = auth.uid()) WITH CHECK (pekerja_id = auth.uid());
CREATE POLICY "pemilik baca semua pelupusan" ON pelupusan_stok FOR SELECT USING (is_pemilik());
CREATE POLICY "pemilik padam pelupusan" ON pelupusan_stok FOR DELETE USING (is_pemilik());

CREATE OR REPLACE FUNCTION lupus_stok_pekerja(p_items jsonb, p_sebab text, p_nota text DEFAULT NULL) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE item jsonb; v_harga_beli float; v_qty int;
BEGIN
  FOR item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_qty := (item->>'qty')::int;
    IF v_qty <= 0 THEN RAISE EXCEPTION 'Kuantiti mesti lebih 0'; END IF;
    UPDATE stok_pekerja SET kuantiti = kuantiti - v_qty
      WHERE pekerja_id = auth.uid() AND stok_id = item->>'stokId' AND kuantiti >= v_qty;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Stok bawaan anda tidak mencukupi untuk %', item->>'stokId';
    END IF;
    SELECT harga_beli INTO v_harga_beli FROM stok WHERE id = item->>'stokId';
    INSERT INTO pelupusan_stok (id, pekerja_id, stok_id, kuantiti, sebab, nota, kos)
      VALUES (gen_random_uuid()::text, auth.uid(), item->>'stokId', v_qty, p_sebab, p_nota, COALESCE(v_harga_beli,0)*v_qty);
  END LOOP;
END;
$$;
GRANT EXECUTE ON FUNCTION lupus_stok_pekerja(jsonb, text, text) TO authenticated;

-- ═══ Baucar Bayaran (Payment Voucher) — rekod audit rasmi bernombor siri untuk upah,
--     petrol & duit makan (jumlah sama seperti dipaparkan dalam Laporan, bukan pengiraan baharu) ═══
CREATE SEQUENCE IF NOT EXISTS baucar_siri_seq;

CREATE TABLE IF NOT EXISTS baucar_bayaran (
  id text PRIMARY KEY,
  no_siri text UNIQUE NOT NULL,
  pekerja_id uuid REFERENCES auth.users(id),
  kategori text NOT NULL CHECK (kategori IN ('petrol','upah','makan')),
  bulan text NOT NULL,
  jumlah float NOT NULL DEFAULT 0,
  tujuan text,
  resit_url text,
  butiran jsonb, -- log perjalanan harian (kategori petrol) — [{tarikh, km, jumlah}]
  status text NOT NULL DEFAULT 'draf' CHECK (status IN ('draf','diluluskan','dibayar')),
  diluluskan_oleh uuid REFERENCES auth.users(id),
  diluluskan_pada timestamptz,
  dibayar_pada timestamptz,
  created_at timestamptz DEFAULT now(),
  UNIQUE(pekerja_id, kategori, bulan)
);
ALTER TABLE baucar_bayaran ENABLE ROW LEVEL SECURITY;
CREATE POLICY "pemilik urus semua baucar" ON baucar_bayaran FOR ALL USING (is_pemilik()) WITH CHECK (is_pemilik());
CREATE POLICY "pekerja baca baucar sendiri" ON baucar_bayaran FOR SELECT USING (pekerja_id = auth.uid());

CREATE OR REPLACE FUNCTION cipta_baucar_bayaran(p_pekerja_id uuid, p_kategori text, p_bulan text, p_jumlah float, p_tujuan text DEFAULT NULL)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_no_siri text; v_id text; v_sedia_id text;
BEGIN
  IF NOT is_pemilik() THEN
    RAISE EXCEPTION 'Hanya pemilik boleh jana baucar bayaran';
  END IF;

  SELECT id INTO v_sedia_id FROM baucar_bayaran
    WHERE pekerja_id = p_pekerja_id AND kategori = p_kategori AND bulan = p_bulan;

  IF v_sedia_id IS NOT NULL THEN
    UPDATE baucar_bayaran SET jumlah = p_jumlah, tujuan = COALESCE(p_tujuan, tujuan)
      WHERE id = v_sedia_id AND status = 'draf';
    RETURN v_sedia_id;
  END IF;

  v_id := gen_random_uuid()::text;
  v_no_siri := 'PV-' || extract(year from now())::text || '-' || lpad(nextval('baucar_siri_seq')::text, 4, '0');
  INSERT INTO baucar_bayaran (id, no_siri, pekerja_id, kategori, bulan, jumlah, tujuan)
  VALUES (v_id, v_no_siri, p_pekerja_id, p_kategori, p_bulan, p_jumlah, p_tujuan);
  RETURN v_id;
END;
$$;
GRANT EXECUTE ON FUNCTION cipta_baucar_bayaran(uuid, text, text, float, text) TO authenticated;

-- ═══ Consignment: sahkan jualan sebenar (pemilik ATAU pekerja yang buat penghantaran asal) —
--     upah pekerja untuk penghantaran consignment hanya dikira selepas jualan disahkan di sini,
--     sokong jualan separa (kuantiti tak terjual tak dikira dalam upah) ═══
CREATE OR REPLACE FUNCTION sahkan_jualan_konsainan(p_transaksi_id text, p_items_terjual jsonb) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_trx RECORD;
  item jsonb;
  v_qty_asal int;
  v_qty_jual int;
BEGIN
  SELECT * INTO v_trx FROM transaksi WHERE id = p_transaksi_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Transaksi tidak dijumpai'; END IF;
  IF NOT (is_pemilik() OR v_trx.created_by = auth.uid()::text) THEN
    RAISE EXCEPTION 'Tidak dibenarkan sahkan jualan transaksi ini';
  END IF;
  IF v_trx.kaedah_bayaran <> 'consignment' THEN RAISE EXCEPTION 'Transaksi ini bukan consignment'; END IF;
  IF v_trx.jualan_disahkan THEN RAISE EXCEPTION 'Jualan sudah disahkan sebelum ini'; END IF;

  FOR item IN SELECT * FROM jsonb_array_elements(p_items_terjual) LOOP
    v_qty_jual := (item->>'qty')::int;
    SELECT (i->>'qty')::int INTO v_qty_asal FROM jsonb_array_elements(v_trx.items) i WHERE i->>'stokId' = item->>'stokId';
    IF v_qty_asal IS NULL OR v_qty_jual IS NULL OR v_qty_jual < 0 OR v_qty_jual > v_qty_asal THEN
      RAISE EXCEPTION 'Kuantiti terjual tidak sah untuk produk %', item->>'stokId';
    END IF;
  END LOOP;

  UPDATE transaksi SET
    items_terjual = p_items_terjual,
    jualan_disahkan = true,
    disahkan_oleh = auth.uid(),
    disahkan_pada = now()
  WHERE id = p_transaksi_id;
END;
$$;
GRANT EXECUTE ON FUNCTION sahkan_jualan_konsainan(text, jsonb) TO authenticated;

-- ═══ Route/Laluan Kedai — kumpulkan kedai kepada laluan bernama untuk memudahkan
--     penghantar servis kedai lama tak dilawati mengikut laluan (auto-susun ikut jarak GPS) ═══
CREATE TABLE IF NOT EXISTS route_kedai (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nama text NOT NULL,
  created_at timestamptz DEFAULT now()
);
ALTER TABLE route_kedai ENABLE ROW LEVEL SECURITY;
CREATE POLICY "staff boleh baca route" ON route_kedai FOR SELECT
  USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid()));
CREATE POLICY "pemilik urus route" ON route_kedai FOR ALL USING (is_pemilik()) WITH CHECK (is_pemilik());

ALTER TABLE kedai ADD COLUMN IF NOT EXISTS route_id uuid REFERENCES route_kedai(id) ON DELETE SET NULL;

-- ═══ Kategori produk boleh edit (medan stok.kategori kekal teks bebas, tak diikat FK) ═══
CREATE TABLE IF NOT EXISTS kategori_stok (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nama text NOT NULL UNIQUE,
  created_at timestamptz DEFAULT now()
);
ALTER TABLE kategori_stok ENABLE ROW LEVEL SECURITY;
CREATE POLICY "staff boleh baca kategori" ON kategori_stok FOR SELECT
  USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid()));
CREATE POLICY "pemilik urus kategori" ON kategori_stok FOR ALL USING (is_pemilik()) WITH CHECK (is_pemilik());
INSERT INTO kategori_stok (nama) VALUES ('Minuman'),('Kesihatan & Kecantikan'),('Makanan'),('Lain-lain') ON CONFLICT (nama) DO NOTHING;
