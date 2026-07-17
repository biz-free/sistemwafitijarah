-- ═══════════════════════════════════════════════════════════
--  WAFI TIJARAH TRADING — SQL TAMBAHAN #32
--  Jalankan SEKALI sahaja dalam Supabase SQL Editor.
--  (Route/Laluan kedai — kumpulkan kedai kepada laluan bernama (cth
--   "Route A") supaya penghantar boleh servis kedai yang lama tak
--   dilawati mengikut laluan yang mudah. Sistem susun kedai dalam
--   setiap route secara automatik ikut jarak GPS berdekatan. Had
--   "Perlu Servis" turut dikurangkan daripada 14 hari ke 7 hari.)
-- ═══════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS route_kedai (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nama text NOT NULL,
  created_at timestamptz DEFAULT now()
);
ALTER TABLE route_kedai ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "staff boleh baca route" ON route_kedai;
CREATE POLICY "staff boleh baca route" ON route_kedai FOR SELECT
  USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid()));
DROP POLICY IF EXISTS "pemilik urus route" ON route_kedai;
CREATE POLICY "pemilik urus route" ON route_kedai FOR ALL USING (is_pemilik()) WITH CHECK (is_pemilik());

ALTER TABLE kedai ADD COLUMN IF NOT EXISTS route_id uuid REFERENCES route_kedai(id) ON DELETE SET NULL;

-- Kategori produk boleh edit (dulu senarai tetap dalam kod) — jadual senarai kategori
-- dibenarkan, medan stok.kategori kekal teks bebas (tak diikat FK) supaya padam kategori
-- tak jejaskan produk sedia ada.
CREATE TABLE IF NOT EXISTS kategori_stok (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nama text NOT NULL UNIQUE,
  created_at timestamptz DEFAULT now()
);
ALTER TABLE kategori_stok ENABLE ROW LEVEL SECURITY;
CREATE POLICY "staff boleh baca kategori" ON kategori_stok FOR SELECT
  USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid()));
CREATE POLICY "pemilik urus kategori" ON kategori_stok FOR ALL USING (is_pemilik()) WITH CHECK (is_pemilik());

-- Seed kategori sedia ada supaya produk lama tak terjejas
INSERT INTO kategori_stok (nama) VALUES ('Minuman'),('Kesihatan & Kecantikan'),('Makanan'),('Lain-lain') ON CONFLICT (nama) DO NOTHING;
