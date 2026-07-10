-- ═══════════════════════════════════════════════════════════
--  WAFI TIJARAH TRADING — SQL TAMBAHAN #20
--  Jalankan SEKALI sahaja dalam Supabase SQL Editor.
--  (Penghantaran percuma pesan.html + Permohonan Ejen & Penghantar)
-- ═══════════════════════════════════════════════════════════

-- ═══ Minima pesanan untuk penghantaran percuma (pesan.html — kedai runcit) ═══
ALTER TABLE tetapan ADD COLUMN IF NOT EXISTS minima_penghantaran_percuma float DEFAULT 100;

-- ═══ Permohonan Ejen & Penghantar Part-Time (pesan.html) ═══
CREATE TABLE IF NOT EXISTS pemohon_program (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  jenis text NOT NULL CHECK (jenis IN ('ejen','penghantar')),
  nama text NOT NULL,
  telefon text NOT NULL,
  kawasan text,
  ada_kenderaan boolean,
  nota text,
  status text DEFAULT 'baru', -- baru / dihubungi / diterima / ditolak
  created_at timestamptz DEFAULT now()
);

ALTER TABLE pemohon_program ENABLE ROW LEVEL SECURITY;
-- Tiada data harga/kewangan di sini — WITH CHECK(true) selamat (bukan seperti
-- pesanan_edagang/pre_order yang kawal jumlah RM sebenar).
DROP POLICY IF EXISTS "sesiapa boleh mohon" ON pemohon_program;
CREATE POLICY "sesiapa boleh mohon" ON pemohon_program FOR INSERT WITH CHECK (true);
DROP POLICY IF EXISTS "staff boleh baca permohonan" ON pemohon_program;
CREATE POLICY "staff boleh baca permohonan" ON pemohon_program FOR SELECT
  USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid()));
DROP POLICY IF EXISTS "staff boleh kemaskini permohonan" ON pemohon_program;
CREATE POLICY "staff boleh kemaskini permohonan" ON pemohon_program FOR UPDATE
  USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid()));
DROP POLICY IF EXISTS "pemilik boleh padam permohonan" ON pemohon_program;
CREATE POLICY "pemilik boleh padam permohonan" ON pemohon_program FOR DELETE USING (is_pemilik());
