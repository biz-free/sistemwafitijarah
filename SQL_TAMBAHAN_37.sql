-- SQL_TAMBAHAN_37: Susulan Bayaran Automatik (1 emel sehari, maksimum 3 kali)
-- Jejak bilangan & tarikh emel susulan dihantar bagi setiap pesanan e-dagang.
-- Selepas 3 emel dihantar & bayaran masih belum selesai, pesanan dibatalkan
-- automatik (data pembeli KEKAL direkod — baris tak dipadam, cuma status
-- ditukar) dan voucher (jika digunakan) dibebaskan untuk guna semula.

ALTER TABLE pesanan_edagang ADD COLUMN IF NOT EXISTS bilangan_susulan int NOT NULL DEFAULT 0;
ALTER TABLE pesanan_edagang ADD COLUMN IF NOT EXISTS susulan_terakhir timestamptz;

-- Enable pg_cron & pg_net (perlu untuk jadualkan panggilan automatik ke Edge Function)
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;
