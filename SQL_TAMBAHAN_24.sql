-- ═══════════════════════════════════════════════════════════
--  WAFI TIJARAH TRADING — SQL TAMBAHAN #24
--  Jalankan SEKALI sahaja dalam Supabase SQL Editor.
--  (Pemilik boleh tugaskan pekerja mana yang urus setiap pesanan
--   e-dagang. Pekerja yang tak ditugaskan tak nampak pesanan itu
--   langsung — bukan sekadar tak boleh ambil.)
-- ═══════════════════════════════════════════════════════════

ALTER TABLE pesanan_edagang ADD COLUMN IF NOT EXISTS assigned_pekerja_id uuid REFERENCES auth.users(id);

-- Gantikan dasar lama "staff boleh baca/kemaskini semua pesanan" dengan dasar
-- yang bezakan pemilik (nampak semua) daripada pekerja (nampak yang ditugaskan sahaja).
DROP POLICY IF EXISTS "staff boleh baca semua pesanan" ON pesanan_edagang;
DROP POLICY IF EXISTS "staff boleh baca pesanan" ON pesanan_edagang;
CREATE POLICY "pemilik baca semua pesanan edagang" ON pesanan_edagang FOR SELECT USING (is_pemilik());
CREATE POLICY "pekerja baca pesanan edagang ditugaskan" ON pesanan_edagang FOR SELECT USING (assigned_pekerja_id = auth.uid());

DROP POLICY IF EXISTS "staff boleh kemaskini pesanan" ON pesanan_edagang;
CREATE POLICY "pemilik kemaskini semua pesanan edagang" ON pesanan_edagang FOR UPDATE USING (is_pemilik());
CREATE POLICY "pekerja kemaskini pesanan edagang ditugaskan" ON pesanan_edagang FOR UPDATE
  USING (assigned_pekerja_id = auth.uid()) WITH CHECK (assigned_pekerja_id = auth.uid());
