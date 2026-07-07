-- ═══════════════════════════════════════════════════════════
--  WAFI TIJARAH TRADING — SQL TAMBAHAN #2
--  Jalankan SEKALI sahaja dalam Supabase SQL Editor.
--  (Anda sudah jalankan SETUP_SQL_LENGKAP.sql sebelum ini — ini cuma TAMBAHAN
--   untuk ciri baharu: Urus Pekerja & Link Pre-Order Kedai)
-- ═══════════════════════════════════════════════════════════

-- ═══ Tambah medan telefon pada profil (untuk papar no. pekerja di resit) ═══
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS telefon text;

-- ═══ Benarkan pemilik daftar & lihat SEMUA profil pekerja ═══
-- (sebelum ini setiap orang cuma boleh baca profil sendiri sahaja)
-- NOTA: guna fungsi is_pemilik() (bukan EXISTS terus ke profiles) supaya
-- elak "infinite recursion" — dasar tak boleh query terus jadual sendiri.
-- Jika anda dah jalankan versi lama fail ini (ada EXISTS terus), sila jalankan
-- SQL_HOTFIX_RECURSION.sql SEGERA untuk baiki.
CREATE OR REPLACE FUNCTION is_pemilik() RETURNS boolean
LANGUAGE sql SECURITY DEFINER SET search_path = public STABLE AS $$
  SELECT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'pemilik');
$$;

CREATE POLICY "pemilik boleh baca semua profil" ON profiles FOR SELECT USING (is_pemilik());
CREATE POLICY "pemilik boleh daftar profil pekerja" ON profiles FOR INSERT WITH CHECK (is_pemilik());

-- ═══ Jadual Pre-Order — pesanan masuk dari kedai melalui link awam pesan.html ═══
CREATE TABLE pre_order (
  id text PRIMARY KEY,
  kedai_nama text NOT NULL,
  kedai_telefon text,
  items jsonb DEFAULT '[]',
  nota text,
  status text DEFAULT 'baru', -- baru / diproses / selesai
  created_at timestamptz DEFAULT now()
);
ALTER TABLE pre_order ENABLE ROW LEVEL SECURITY;

-- Sesiapa sahaja (tanpa log masuk) boleh HANTAR pre-order dari borang awam
CREATE POLICY "sesiapa boleh hantar pre-order" ON pre_order FOR INSERT WITH CHECK (true);
-- Hanya staff (pemilik/pekerja log masuk) boleh BACA & KEMASKINI pre-order
CREATE POLICY "staff boleh baca pre-order" ON pre_order FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "staff boleh kemaskini pre-order" ON pre_order FOR UPDATE USING (auth.role() = 'authenticated');

-- ═══ Fungsi awam — senarai produk (tanpa harga beli/modal) untuk borang pre-order ═══
CREATE OR REPLACE FUNCTION senarai_produk_awam()
RETURNS TABLE(id text, nama text, unit text, harga_jual float, kategori text)
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT id, nama, unit, harga_jual, kategori FROM stok ORDER BY nama;
$$;
GRANT EXECUTE ON FUNCTION senarai_produk_awam() TO anon, authenticated;
