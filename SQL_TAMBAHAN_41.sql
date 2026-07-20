-- SQL_TAMBAHAN_41: Jejak kunjungan website sendiri (tanpa perlu buka Google
-- Analytics) — setiap kali index.html/pesan.html dibuka, satu rekod ringkas
-- disimpan (halaman, saluran/sumber, session) supaya pemilik boleh lihat
-- trafik terus dalam tab "📈 Analisis" (pengurusan.html).

CREATE TABLE IF NOT EXISTS kunjungan_web (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  halaman text NOT NULL,
  saluran text NOT NULL DEFAULT 'Direct/Lain',
  utm_source text,
  utm_campaign text,
  referrer text,
  session_id text,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_kunjungan_web_created_at ON kunjungan_web(created_at);

ALTER TABLE kunjungan_web ENABLE ROW LEVEL SECURITY;

-- Sesiapa (pelawat awam, tanpa log masuk) boleh rekod kunjungan — tiada data
-- peribadi disimpan (bukan nama/telefon/IP), cuma halaman + saluran + session id rawak.
DROP POLICY IF EXISTS "sesiapa boleh rekod kunjungan" ON kunjungan_web;
CREATE POLICY "sesiapa boleh rekod kunjungan" ON kunjungan_web FOR INSERT WITH CHECK (true);

-- Hanya pemilik boleh baca statistik kunjungan (elak pesaing/orang lain scrape data trafik).
DROP POLICY IF EXISTS "pemilik boleh baca kunjungan" ON kunjungan_web;
CREATE POLICY "pemilik boleh baca kunjungan" ON kunjungan_web FOR SELECT USING (is_pemilik());
