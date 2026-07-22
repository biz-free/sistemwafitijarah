-- SQL_TAMBAHAN_44: Kempen Win-Back Automatik — hantar emel "kami rindu awak"
-- kepada pelanggan yang sudah lama tidak membeli (default 60 hari), dengan
-- cooldown supaya tidak dihantar berulang-ulang kepada pelanggan sama
-- (default 90 hari). Dijalankan mingguan melalui pg_cron + Edge Function
-- winback-auto-cron (lihat langkah setup dalam PANDUAN_SETUP.md).

-- Tetapan kempen — baris tunggal sama seperti tetapan lain.
ALTER TABLE tetapan ADD COLUMN IF NOT EXISTS winback_aktif boolean NOT NULL DEFAULT false;
ALTER TABLE tetapan ADD COLUMN IF NOT EXISTS winback_hari_tidak_aktif int NOT NULL DEFAULT 60;
ALTER TABLE tetapan ADD COLUMN IF NOT EXISTS winback_cooldown_hari int NOT NULL DEFAULT 90;
ALTER TABLE tetapan ADD COLUMN IF NOT EXISTS winback_kod_voucher text;

-- Log setiap emel win-back yang dihantar — untuk elak hantar berulang dalam
-- tempoh cooldown, dan untuk pemilik lihat sejarah kempen dalam pengurusan.html.
CREATE TABLE IF NOT EXISTS winback_log (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  telefon text NOT NULL,
  email text,
  nama text,
  tarikh_pesanan_terakhir timestamptz,
  kod_voucher text,
  dihantar_pada timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_winback_log_telefon ON winback_log(telefon);
CREATE INDEX IF NOT EXISTS idx_winback_log_dihantar ON winback_log(dihantar_pada);

ALTER TABLE winback_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "pemilik baca winback_log" ON winback_log;
CREATE POLICY "pemilik baca winback_log" ON winback_log FOR SELECT USING (is_pemilik());
-- Tiada policy INSERT/UPDATE untuk client — hanya Edge Function (service_role,
-- bypass RLS) yang tulis rekod, elak sesiapa cipta/palsukan log kempen.
