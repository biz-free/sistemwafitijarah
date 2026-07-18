-- SQL_TAMBAHAN_35: Mesej Promosi (Notifikasi Bergerak) untuk laman utama (index.html)
-- Pemilik masukkan sebarang makluman/promosi voucher di tab "Kod Voucher" (pengurusan.html)
-- — dipaparkan sebagai notifikasi emas bergerak dari kanan ke kiri di laman utama pelanggan.

ALTER TABLE tetapan ADD COLUMN IF NOT EXISTS promo_mesej text;
