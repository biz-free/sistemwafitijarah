-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 160: Status lokasi 🔴/🟢 dalam notifikasi Telegram baucar harian
--
-- PUNCA (arahan Amirul 2026-10-05): amaran "Semak lokasi kedai sebelum
-- luluskan (jejaskan kiraan minyak)" sedia ada HANYA dipapar dalam app
-- (pengurusan.html, senarai Baucar Bayaran) — Amirul terpaksa buka app
-- setiap kali nak tahu ada isu lokasi atau tidak sebelum luluskan baucar
-- harian daripada notifikasi Telegram yang diterima.
--
-- PENYELESAIAN: semula logik kesanKedaiMencurigakanHariIni() (client-side,
-- pengurusan.html) sebagai fungsi pangkalan data, supaya Edge Function
-- notifikasi-kelulusan-pemilik boleh panggil terus (RPC) dan sertakan
-- status 🔴 (ada isu, perlu semak) atau 🟢 (tiada isu) dalam mesej Telegram
-- itu sendiri — Amirul boleh tahu terus tanpa buka app. Hanya terpakai
-- untuk baucar_bayaran kategori='upah_harian' (kos minyak); jenis lain
-- dianggap 🟢 (tiada semakan lokasi berkenaan).
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
  WHERE (jarak_pin_gps_km > 5) OR (jumlah_titik >= 2 AND jarak_terdekat > 15);

  IF amaran IS NOT NULL AND array_length(amaran, 1) > 0 THEN
    RETURN QUERY SELECT 'merah'::text, array_to_string(amaran, ' | ');
  ELSE
    RETURN QUERY SELECT 'hijau'::text, NULL::text;
  END IF;
END;
$function$;

-- NOTA: perubahan kod Edge Function sahaja (bukan SQL) — deploy semula fungsi
-- notifikasi-kelulusan-pemilik dari kod sumber terkini (supabase/functions/
-- notifikasi-kelulusan-pemilik/index.ts) selepas jalankan SQL ni.
