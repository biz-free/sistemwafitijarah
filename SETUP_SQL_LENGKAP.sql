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

CREATE OR REPLACE FUNCTION senarai_produk_awam()
RETURNS TABLE(id text, nama text, unit text, harga_jual float, kategori text, gambar_url text, gambar_urls jsonb, jumlah_terjual bigint)
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT s.id, s.nama, s.unit, s.harga_jual, s.kategori, s.gambar_url, s.gambar_urls,
    COALESCE((SELECT SUM((item->>'qty')::int) FROM transaksi t, jsonb_array_elements(t.items) item WHERE item->>'stokId' = s.id), 0) AS jumlah_terjual
  FROM stok s ORDER BY nama;
$$;
GRANT EXECUTE ON FUNCTION senarai_produk_awam() TO anon, authenticated;

-- ═══ Padam data (pemilik sahaja) ═══
CREATE POLICY "pemilik padam stok" ON stok FOR DELETE USING (is_pemilik());
CREATE POLICY "pemilik padam kedai" ON kedai FOR DELETE USING (is_pemilik());
CREATE POLICY "pemilik padam transaksi" ON transaksi FOR DELETE USING (is_pemilik());
CREATE POLICY "pemilik padam pre_order" ON pre_order FOR DELETE USING (is_pemilik());
CREATE POLICY "pemilik padam kehadiran" ON kehadiran FOR DELETE USING (is_pemilik());
CREATE POLICY "pemilik padam permohonan_cuti" ON permohonan_cuti FOR DELETE USING (is_pemilik());
CREATE POLICY "pemilik padam stok_pekerja" ON stok_pekerja FOR DELETE USING (is_pemilik());

-- ═══ Notifikasi ringkas — kiraan siap (tiada jadual baharu, kira terus dari data sedia ada) ═══
-- Pemilik: bilangan permohonan cuti "menunggu" + pre-order "baru"
-- Pekerja: bilangan pre-order "baru" yang belum ditugaskan
-- (Dikira terus di client bila diperlukan — tiada perubahan skema untuk ini)
-- (Gambar berbilang & jumlah_terjual sudah termasuk dalam senarai_produk_awam versi ini)
