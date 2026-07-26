-- SQL_TAMBAHAN_58: Permohonan Padam (pekerja minta, pemilik lulus) + kebenaran
-- padam baucar bayaran untuk pemilik.
--
-- 1) PERMOHONAN PADAM
-- Pekerja tiada kebenaran padam rekod (dan memang tak sepatutnya — padam
-- kekal melibatkan audit/kewangan). Sebelum ini pekerja terpaksa hubungi
-- pemilik luar sistem. Kini setiap tempat pemilik ada ikon "✕ Padam",
-- pekerja nampak ikon "🗑️ Minta Padam" — permohonan direkod di sini,
-- pemilik semak & luluskan (barulah padam sebenar berlaku).
--
-- Sengaja TIDAK simpan foreign key kepada rekod sasaran: rekod itu akan
-- dipadam bila permohonan diluluskan, dan jadual sasaran berbeza-beza
-- (kedai/pre_order/baucar_bayaran/...). Simpan jenis + id + label teks
-- supaya sejarah permohonan kekal terbaca walaupun rekod sudah tiada.
CREATE TABLE IF NOT EXISTS permohonan_padam (
  id text PRIMARY KEY,
  jenis text NOT NULL,               -- cth 'kedai', 'pre_order', 'baucar_bayaran'
  rekod_id text NOT NULL,
  rekod_label text,                  -- nama/no. siri untuk paparan pemilik
  sebab text,
  pekerja_id uuid REFERENCES auth.users(id),
  status text NOT NULL DEFAULT 'menunggu',
  diputuskan_oleh uuid REFERENCES auth.users(id),
  diputuskan_pada timestamptz,
  created_at timestamptz DEFAULT now(),
  CONSTRAINT permohonan_padam_status_check
    CHECK (status = ANY (ARRAY['menunggu'::text, 'diluluskan'::text, 'ditolak'::text]))
);

-- Elak permohonan berganda untuk rekod sama yang masih menunggu
CREATE UNIQUE INDEX IF NOT EXISTS permohonan_padam_unik_menunggu
  ON permohonan_padam (jenis, rekod_id) WHERE status = 'menunggu';

ALTER TABLE permohonan_padam ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "pekerja hantar permohonan padam" ON permohonan_padam;
CREATE POLICY "pekerja hantar permohonan padam" ON permohonan_padam
  FOR INSERT WITH CHECK (auth.uid() = pekerja_id);

DROP POLICY IF EXISTS "staff baca permohonan padam" ON permohonan_padam;
CREATE POLICY "staff baca permohonan padam" ON permohonan_padam
  FOR SELECT USING (is_pemilik() OR pekerja_id = auth.uid());

DROP POLICY IF EXISTS "pemilik putuskan permohonan padam" ON permohonan_padam;
CREATE POLICY "pemilik putuskan permohonan padam" ON permohonan_padam
  FOR UPDATE USING (is_pemilik()) WITH CHECK (is_pemilik());

DROP POLICY IF EXISTS "pemilik padam permohonan padam" ON permohonan_padam;
CREATE POLICY "pemilik padam permohonan padam" ON permohonan_padam
  FOR DELETE USING (is_pemilik());

-- 2) Pemilik boleh padam BAUCAR BAYARAN yang dijana
-- (jadual ini sebelum ini tiada polisi DELETE langsung — baucar tersalah
-- jana tak boleh dibuang, hanya boleh ditukar status).
DROP POLICY IF EXISTS "pemilik padam baucar bayaran" ON baucar_bayaran;
CREATE POLICY "pemilik padam baucar bayaran" ON baucar_bayaran
  FOR DELETE USING (is_pemilik());
