-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 122: Kempen Ajakan Affiliate (susulan automatik) +
-- Notifikasi Komisen Affiliate (push+emel bila pemilik sahkan bayaran)
--
-- 1. Jadual `ajakan_affiliate` jejak setiap pembeli lama (emel) yang belum
--    jadi affiliate — dihantar emel ajakan setiap 3 hari, maksimum 3 kali,
--    berhenti automatik jika mereka daftar (padan emel Google mereka) atau
--    cecah had percubaan. Sama pola dgn susulan-bayaran-harian sedia ada.
-- 2. Trigger `cipta_pendapatan_affiliate` dikemaskini — lepas rekod
--    pendapatan affiliate berjaya (pesanan disahkan bayar), hantar push+emel
--    terus kepada affiliate berkenaan (Edge Function baharu
--    notifikasi-komisen-affiliate).
-- ═══════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS ajakan_affiliate (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  emel text NOT NULL UNIQUE,
  nama text,
  bilangan_dihantar int NOT NULL DEFAULT 0,
  dihantar_terakhir timestamptz,
  status text NOT NULL DEFAULT 'menunggu', -- menunggu | didaftar | berhenti
  created_at timestamptz DEFAULT now()
);
ALTER TABLE ajakan_affiliate ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "pemilik baca ajakan_affiliate" ON ajakan_affiliate;
CREATE POLICY "pemilik baca ajakan_affiliate" ON ajakan_affiliate FOR SELECT USING ((select is_pemilik()));

SELECT cron.schedule(
  'ajakan-affiliate-harian',
  '0 19 * * *',
  $$
  select net.http_post(
    url := 'https://smepriytkoxkmpvjvvzq.supabase.co/functions/v1/ajakan-affiliate-cron',
    headers := '{"Content-Type": "application/json", "x-cron-secret": "8b225dc5444b19fe2c07b9ca72ba14d9c52b1bf193007049"}'::jsonb,
    body := '{}'::jsonb
  );
  $$
);

-- ── Notifikasi komisen affiliate (push+emel) selepas pendapatan direkod ──
CREATE OR REPLACE FUNCTION public.cipta_pendapatan_affiliate()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_affiliate RECORD;
  v_jumlah_komisen numeric;
BEGIN
  IF NEW.status_bayaran = 'disahkan' AND OLD.status_bayaran IS DISTINCT FROM 'disahkan'
     AND NEW.kod_affiliate IS NOT NULL AND NEW.kod_affiliate <> '' THEN
    SELECT id, kadar_komisen_peratus INTO v_affiliate FROM affiliates WHERE kod_affiliate = NEW.kod_affiliate AND status = 'aktif';
    IF v_affiliate.id IS NOT NULL THEN
      v_jumlah_komisen := ROUND((NEW.subjumlah * v_affiliate.kadar_komisen_peratus / 100)::numeric, 2);
      INSERT INTO affiliate_earnings (id, affiliate_id, pesanan_id, jumlah_pesanan, kadar_komisen_peratus, jumlah_komisen, tarikh_boleh_tuntut)
      VALUES (gen_random_uuid()::text, v_affiliate.id, NEW.id, NEW.subjumlah, v_affiliate.kadar_komisen_peratus, v_jumlah_komisen, (CURRENT_DATE + INTERVAL '14 days')::date)
      ON CONFLICT (pesanan_id) DO NOTHING;

      IF FOUND THEN
        PERFORM net.http_post(
          url := 'https://smepriytkoxkmpvjvvzq.supabase.co/functions/v1/notifikasi-komisen-affiliate',
          headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNtZXByaXl0a294a21wdmp2dnpxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMzODE1OTcsImV4cCI6MjA5ODk1NzU5N30.bLDjFNZ_gMm9ufCkA4TeFbw1rysuLnlQN-qW_WW0zr8'
          ),
          body := jsonb_build_object(
            'affiliate_id', v_affiliate.id,
            'pesanan_id', NEW.id,
            'jumlah_pesanan', NEW.subjumlah,
            'jumlah_komisen', v_jumlah_komisen
          )
        );
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;
