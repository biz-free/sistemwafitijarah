-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 108: Notifikasi EMEL automatik untuk invois yang telah
-- melepasi tarikh akhir bayaran — dihantar kepada PEKERJA yang buat
-- penghantaran (created_by) DAN PEMILIK, sekali sahaja per invois
-- (bukan diulang setiap hari selagi belum bayar).
--
-- Edge Function: notifikasi-invois-lewat-cron (guna semula secret
-- RESEND_API_KEY & CRON_SECRET sedia ada — tiada secret baharu).
-- Dijadualkan jalan sekali sehari, 01:00 waktu Malaysia (17:00 UTC
-- hari sebelumnya) — lepas cron lucuthak-diskaun-harian (00:30 MY)
-- supaya emel turut cerminkan jumlah TERKINI (selepas diskaun
-- dilucuthak, jika berkaitan).
-- ═══════════════════════════════════════════════════════════

ALTER TABLE public.transaksi ADD COLUMN IF NOT EXISTS notifikasi_lewat_dihantar boolean NOT NULL DEFAULT false;

-- Jalankan SEKALI di SQL Editor Supabase, gantikan <CRON_SECRET> dgn nilai SAMA
-- seperti susulan-bayaran-harian/kempen-winback-mingguan/rujukan-ganjaran (jangan
-- commit nilai sebenar secret ke git — lihat corak sedia ada SQL_TAMBAHAN_37/44/45).
SELECT cron.schedule(
  'notifikasi-invois-lewat-harian',
  '0 17 * * *',
  $$
  select net.http_post(
    url := 'https://smepriytkoxkmpvjvvzq.supabase.co/functions/v1/notifikasi-invois-lewat-cron',
    headers := '{"Content-Type": "application/json", "x-cron-secret": "<CRON_SECRET>"}'::jsonb,
    body := '{}'::jsonb
  );
  $$
);

-- Untuk lihat/urus jadual cron: select * from cron.job;
-- Untuk padam jadual ni: select cron.unschedule('notifikasi-invois-lewat-harian');
