-- ═══════════════════════════════════════════════════════════
--  WAFI TIJARAH TRADING — SQL SETUP LENGKAP
--  Jalankan SEKALI sahaja dalam Supabase SQL Editor (project: smepriytkoxkmpvjvvzq)
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
  created_at timestamptz DEFAULT now()
);

CREATE TABLE transaksi (
  id text PRIMARY KEY,
  tarikh_masa timestamptz DEFAULT now(),
  kedai_id text REFERENCES kedai(id),
  items jsonb DEFAULT '[]',
  jumlah float DEFAULT 0,
  status text DEFAULT 'selesai',
  nota text,
  resit text,
  jarak_km float DEFAULT 0,
  created_by text
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

-- Pesanan masuk dari kedai melalui link awam pesan.html (repeat order)
CREATE TABLE pre_order (
  id text PRIMARY KEY,
  kedai_nama text NOT NULL,
  kedai_telefon text,
  items jsonb DEFAULT '[]',
  nota text,
  status text DEFAULT 'baru', -- baru / diproses / selesai
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

-- ═══ Row Level Security ═══
ALTER TABLE stok ENABLE ROW LEVEL SECURITY;
ALTER TABLE kedai ENABLE ROW LEVEL SECURITY;
ALTER TABLE transaksi ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE pre_order ENABLE ROW LEVEL SECURITY;
ALTER TABLE kehadiran ENABLE ROW LEVEL SECURITY;
ALTER TABLE gps_track ENABLE ROW LEVEL SECURITY;

-- Fungsi SECURITY DEFINER supaya semakan peranan pemilik TIDAK query terus
-- profiles dari dalam dasar profiles sendiri (elak "infinite recursion").
CREATE OR REPLACE FUNCTION is_pemilik() RETURNS boolean
LANGUAGE sql SECURITY DEFINER SET search_path = public STABLE AS $$
  SELECT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'pemilik');
$$;

CREATE POLICY "pekerja urus kehadiran sendiri" ON kehadiran FOR ALL USING (pekerja_id = auth.uid()) WITH CHECK (pekerja_id = auth.uid());
CREATE POLICY "pemilik baca semua kehadiran" ON kehadiran FOR SELECT USING (is_pemilik());
CREATE POLICY "pekerja tambah gps sendiri" ON gps_track FOR INSERT WITH CHECK (pekerja_id = auth.uid());
CREATE POLICY "pekerja baca gps sendiri" ON gps_track FOR SELECT USING (pekerja_id = auth.uid());
CREATE POLICY "pemilik baca semua gps" ON gps_track FOR SELECT USING (is_pemilik());

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
CREATE POLICY "pemilik tambah kedai" ON kedai FOR INSERT WITH CHECK (
  EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'pemilik')
);
CREATE POLICY "pemilik kemaskini kedai" ON kedai FOR UPDATE USING (
  EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'pemilik')
);

-- Pre-order: sesiapa (tanpa log masuk) boleh hantar; hanya staff boleh baca/kemaskini
CREATE POLICY "sesiapa boleh hantar pre-order" ON pre_order FOR INSERT WITH CHECK (true);
CREATE POLICY "staff boleh baca pre-order" ON pre_order FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "staff boleh kemaskini pre-order" ON pre_order FOR UPDATE USING (auth.role() = 'authenticated');

-- ═══ Fungsi RPC — kemaskini stok/hutang secara atomik ═══
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

  FOR item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    UPDATE stok SET stok = stok - (item->>'qty')::int WHERE id = item->>'stokId';
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Produk % tidak wujud', item->>'stokId';
    END IF;
  END LOOP;

  IF EXISTS (
    SELECT 1 FROM stok s JOIN jsonb_array_elements(p_items) i ON s.id = i->>'stokId' WHERE s.stok < 0
  ) THEN
    RAISE EXCEPTION 'Stok tidak mencukupi untuk salah satu produk';
  END IF;

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

-- ═══ Fungsi awam — senarai produk (tanpa harga beli/modal) untuk borang pre-order ═══
CREATE OR REPLACE FUNCTION senarai_produk_awam()
RETURNS TABLE(id text, nama text, unit text, harga_jual float, kategori text)
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT id, nama, unit, harga_jual, kategori FROM stok ORDER BY nama;
$$;
GRANT EXECUTE ON FUNCTION senarai_produk_awam() TO anon, authenticated;

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
