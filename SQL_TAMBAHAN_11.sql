-- ═══════════════════════════════════════════════════════════
--  WAFI TIJARAH TRADING — SQL TAMBAHAN #11
--  Jalankan SEKALI sahaja dalam Supabase SQL Editor.
--  (Fasa 1 — Laman E-Dagang: zon penghantaran, pesanan awam)
--  Guna semula jadual `stok` sedia ada sebagai katalog produk —
--  tiada jadual produk berasingan diperlukan.
-- ═══════════════════════════════════════════════════════════

-- ═══ Zon Penghantaran (kadar shipping ikut kawasan) ═══
CREATE TABLE IF NOT EXISTS zon_penghantaran (
  id text PRIMARY KEY,
  nama text NOT NULL,
  kadar_asas float DEFAULT 0,
  kadar_per_kg float DEFAULT 0,
  anggaran_hari text
);

ALTER TABLE zon_penghantaran ENABLE ROW LEVEL SECURITY;
CREATE POLICY "semua boleh baca zon" ON zon_penghantaran FOR SELECT USING (true);
CREATE POLICY "pemilik urus zon" ON zon_penghantaran FOR ALL USING (is_pemilik());

INSERT INTO zon_penghantaran (id, nama, kadar_asas, kadar_per_kg, anggaran_hari) VALUES
  ('semenanjung', 'Semenanjung Malaysia', 6, 1.5, '2-4 hari bekerja'),
  ('sabah_sarawak', 'Sabah & Sarawak', 12, 3, '4-7 hari bekerja')
ON CONFLICT (id) DO NOTHING;

-- ═══ Pesanan E-Dagang (guest checkout, tiada log masuk diperlukan) ═══
CREATE TABLE IF NOT EXISTS pesanan_edagang (
  id text PRIMARY KEY,
  pelanggan_nama text NOT NULL,
  pelanggan_telefon text NOT NULL,
  pelanggan_email text,
  items jsonb DEFAULT '[]',
  subjumlah float DEFAULT 0,
  kos_penghantaran float DEFAULT 0,
  diskaun float DEFAULT 0,
  jumlah float DEFAULT 0,
  alamat text,
  poskod text,
  negeri text,
  zon_penghantaran text REFERENCES zon_penghantaran(id),
  nama_kurier text,
  no_tracking text,
  kaedah_bayaran text DEFAULT 'transfer',
  status_bayaran text DEFAULT 'menunggu',
  status_pesanan text DEFAULT 'baru',
  nota text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE pesanan_edagang ENABLE ROW LEVEL SECURITY;
CREATE POLICY "sesiapa boleh buat pesanan" ON pesanan_edagang FOR INSERT WITH CHECK (true);
CREATE POLICY "staff boleh baca pesanan" ON pesanan_edagang FOR SELECT USING (auth.uid() IS NOT NULL);
CREATE POLICY "staff boleh kemaskini pesanan" ON pesanan_edagang FOR UPDATE USING (auth.uid() IS NOT NULL);
CREATE POLICY "pemilik boleh padam pesanan" ON pesanan_edagang FOR DELETE USING (is_pemilik());

-- ═══ Baucar Diskaun (Fasa 2 — belum digunakan lagi, sedia untuk masa depan) ═══
CREATE TABLE IF NOT EXISTS baucar (
  kod text PRIMARY KEY,
  jenis_diskaun text DEFAULT 'peratus',
  nilai_diskaun float DEFAULT 0,
  minima_belanja float DEFAULT 0,
  tarikh_luput date,
  aktif boolean DEFAULT true
);

ALTER TABLE baucar ENABLE ROW LEVEL SECURITY;
CREATE POLICY "semua boleh baca baucar aktif" ON baucar FOR SELECT USING (aktif = true);
CREATE POLICY "pemilik urus baucar" ON baucar FOR ALL USING (is_pemilik());
