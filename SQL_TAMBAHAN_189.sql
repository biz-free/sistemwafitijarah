-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 189: Pin kedai disahkan GPS (jarak_pin_gps_km) — amaran "terasing" palsu
--
-- PUNCA (baucar Nadia 21 Nov 2026): amaran "~44km terasing drpd kedai lain hari sama"
-- keluar walaupun pin kedai tepat (Kubur Panjang 0.007km, Merbok 0.53km dari GPS Nadia
-- semasa jualan). Kedai memang berjauhan, tapi pekerja memang ada di situ.
--
-- PENYELESAIAN: (1) kesan_kedai_mencurigakan_baucar: isyarat "terasing" HANYA dipakai bila
-- jarak_pin_gps_km tiada (rekod lama); bila ada & <=5km, pin dianggap sah.
-- (2) pin_disahkan_gps_baucar(): senarai kedai berpin-sah utk dipapar sbg baris
-- "📍 Pin disahkan GPS: ..." dlm Telegram pemilik (ditapis dari WhatsApp Team Sales oleh
-- sulitkanUntukWa() dlm telegram-webhook).
-- Selepas jalankan SQL: deploy semula notifikasi-kelulusan-pemilik + telegram-webhook.
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.kesan_kedai_mencurigakan_baucar(p_baucar_id text)
RETURNS TABLE(status text, mesej text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_pekerja_id uuid;
  v_tarikh date;
  v_kategori text;
  amaran text[];
BEGIN
  SELECT pekerja_id, tarikh, kategori INTO v_pekerja_id, v_tarikh, v_kategori
  FROM baucar_bayaran WHERE id = p_baucar_id;

  IF v_pekerja_id IS NULL OR v_kategori IS DISTINCT FROM 'upah_harian' THEN
    RETURN QUERY SELECT 'hijau'::text, NULL::text;
    RETURN;
  END IF;

  WITH titik AS (
    SELECT DISTINCT k.id, k.nama, k.lat, k.lng, k.jarak_pin_gps_km
    FROM transaksi t
    JOIN kedai k ON k.id = t.kedai_id
    WHERE t.created_by = v_pekerja_id::text
      AND (t.tarikh_masa AT TIME ZONE 'Asia/Kuala_Lumpur')::date = v_tarikh
      AND k.lat IS NOT NULL AND k.lng IS NOT NULL
  ), jarak AS (
    SELECT a.id, a.nama, a.jarak_pin_gps_km,
           MIN(2 * 6371 * asin(sqrt(
             sin(radians(b.lat - a.lat) / 2) ^ 2 +
             cos(radians(a.lat)) * cos(radians(b.lat)) * sin(radians(b.lng - a.lng) / 2) ^ 2
           ))) FILTER (WHERE b.id <> a.id) AS jarak_terdekat,
           (SELECT count(*) FROM titik) AS jumlah_titik
    FROM titik a LEFT JOIN titik b ON true
    GROUP BY a.id, a.nama, a.jarak_pin_gps_km
  )
  SELECT array_agg(
    nama || CASE
      WHEN jarak_pin_gps_km > 5 THEN ' — pin didaftar ' || round(jarak_pin_gps_km::numeric, 1) || 'km dari GPS pekerja masa tu'
      ELSE ' — ~' || round(jarak_terdekat::numeric, 0) || 'km terasing drpd kedai lain hari sama, sila sahkan bukan silap pin'
    END
  ) INTO amaran
  FROM jarak
  WHERE (jarak_pin_gps_km > 5)
     OR (jumlah_titik >= 2 AND jarak_terdekat > 15 AND jarak_pin_gps_km IS NULL);

  IF amaran IS NOT NULL AND array_length(amaran, 1) > 0 THEN
    RETURN QUERY SELECT 'merah'::text, array_to_string(amaran, ' | ');
  ELSE
    RETURN QUERY SELECT 'hijau'::text, NULL::text;
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.pin_disahkan_gps_baucar(p_baucar_id text)
RETURNS text
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT string_agg(
           k.nama || ' (' ||
           CASE WHEN k.jarak_pin_gps_km < 1 THEN round(k.jarak_pin_gps_km::numeric * 1000)::text || 'm'
                ELSE round(k.jarak_pin_gps_km::numeric, 1)::text || 'km' END || ')',
           ', ' ORDER BY k.nama)
  FROM baucar_bayaran b
  JOIN LATERAL (
    SELECT DISTINCT k2.id FROM transaksi t JOIN kedai k2 ON k2.id = t.kedai_id
    WHERE t.created_by = b.pekerja_id::text
      AND (t.tarikh_masa AT TIME ZONE 'Asia/Kuala_Lumpur')::date = b.tarikh
  ) x ON true
  JOIN kedai k ON k.id = x.id
  WHERE b.id = p_baucar_id AND b.kategori = 'upah_harian'
    AND k.jarak_pin_gps_km IS NOT NULL AND k.jarak_pin_gps_km <= 5;
$function$;
