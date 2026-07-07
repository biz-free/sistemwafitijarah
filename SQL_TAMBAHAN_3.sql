-- ═══════════════════════════════════════════════════════════
--  WAFI TIJARAH TRADING — SQL TAMBAHAN #3
--  Jalankan SEKALI sahaja dalam Supabase SQL Editor.
--  (Untuk ciri: Reset Kata Laluan Pekerja, Thumb In/Out & Jejak GPS)
-- ═══════════════════════════════════════════════════════════

-- ═══ Medan tambahan pada profil ═══
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS must_change_password boolean DEFAULT false;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS webauthn_credential_id text;

-- ═══ Jadual Kehadiran (Thumb In/Out) ═══
CREATE TABLE kehadiran (
  id text PRIMARY KEY,
  pekerja_id uuid REFERENCES auth.users(id),
  thumb_in_masa timestamptz,
  thumb_in_lat float,
  thumb_in_lng float,
  thumb_out_masa timestamptz,
  thumb_out_lat float,
  thumb_out_lng float,
  status text DEFAULT 'aktif', -- aktif / selesai
  created_at timestamptz DEFAULT now()
);

-- ═══ Jadual Jejak GPS (setiap 30 minit semasa kehadiran aktif) ═══
CREATE TABLE gps_track (
  id bigserial PRIMARY KEY,
  kehadiran_id text REFERENCES kehadiran(id) ON DELETE CASCADE,
  pekerja_id uuid REFERENCES auth.users(id),
  lat float,
  lng float,
  tarikh_masa timestamptz DEFAULT now()
);

ALTER TABLE kehadiran ENABLE ROW LEVEL SECURITY;
ALTER TABLE gps_track ENABLE ROW LEVEL SECURITY;

-- Pekerja boleh urus rekod kehadiran diri sendiri sahaja (thumb in = insert, thumb out = update)
CREATE POLICY "pekerja urus kehadiran sendiri" ON kehadiran FOR ALL USING (pekerja_id = auth.uid()) WITH CHECK (pekerja_id = auth.uid());
-- Pemilik boleh baca kehadiran semua pekerja (untuk laporan & claim minyak)
-- Guna fungsi is_pemilik() (dari SQL_TAMBAHAN_2.sql) — bukan EXISTS terus,
-- supaya konsisten & elak isu "infinite recursion" pada profiles.
CREATE POLICY "pemilik baca semua kehadiran" ON kehadiran FOR SELECT USING (is_pemilik());

CREATE POLICY "pekerja tambah gps sendiri" ON gps_track FOR INSERT WITH CHECK (pekerja_id = auth.uid());
CREATE POLICY "pekerja baca gps sendiri" ON gps_track FOR SELECT USING (pekerja_id = auth.uid());
CREATE POLICY "pemilik baca semua gps" ON gps_track FOR SELECT USING (is_pemilik());
