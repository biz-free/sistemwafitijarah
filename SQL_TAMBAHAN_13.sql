-- ═══════════════════════════════════════════════════════════
--  WAFI TIJARAH TRADING — SQL TAMBAHAN #13
--  Jalankan SEKALI sahaja dalam Supabase SQL Editor.
--  (Fasa 3a — Sambungan EasyParcel OAuth)
-- ═══════════════════════════════════════════════════════════

-- Satu baris sahaja (id=1) — simpan token OAuth EasyParcel.
-- PENTING: jadual ini SENGAJA tiada polisi SELECT/INSERT/UPDATE untuk
-- anon/authenticated — access_token & refresh_token hanya boleh dibaca/
-- ditulis oleh Edge Function (guna service_role key, yang pintas RLS).
-- Ini elak sesiapa (termasuk pemilik log masuk) terus lihat token mentah
-- melalui client-side code.
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
-- (Sengaja tiada CREATE POLICY — jadual tertutup sepenuhnya dari client.)

-- Fungsi awam (staff sahaja) untuk semak status sambungan TANPA dedah token.
CREATE OR REPLACE FUNCTION easyparcel_status()
RETURNS TABLE(connected boolean, connected_at timestamptz, expires_at timestamptz)
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT (access_token IS NOT NULL), connected_at, expires_at FROM easyparcel_auth WHERE id = 1;
$$;
GRANT EXECUTE ON FUNCTION easyparcel_status() TO authenticated;
