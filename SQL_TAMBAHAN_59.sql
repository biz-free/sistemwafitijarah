-- SQL_TAMBAHAN_59: Auto-isi butiran kedai daripada no. telefon di borang pre-order
--
-- Sebelum ini kedai yang SUDAH berdaftar terpaksa taip semula nama & alamat
-- setiap kali buat pre-order (kecuali jika mereka masuk melalui link QR yang
-- membawa ?kedai=<id>). Kedai yang simpan link biasa / taip URL sendiri
-- terpaksa key-in semula — menyusahkan dan menyebabkan nama/alamat tak konsisten
-- (kedai sama tercipta berkali-kali dengan ejaan berbeza).
--
-- RPC ini membenarkan borang AWAM (anon) mencari kedai ikut no. telefon.
-- SECURITY DEFINER kerana pesan.html tiada sesi log masuk & RLS `kedai`
-- hanya benarkan staff. Sengaja hanya dedah nama/alamat/lat/lng — TIADA
-- hutang, harga, atau data kewangan lain.
--
-- Padanan mengabaikan format (ruang, '-', awalan 0/60) supaya '013-463 6383',
-- '0134636383' dan '60134636383' semuanya menemui kedai yang sama.
CREATE OR REPLACE FUNCTION public.cari_kedai_ikut_telefon(p_telefon text)
RETURNS TABLE(id text, nama text, telefon text, alamat text, lat double precision, lng double precision)
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  WITH input AS (
    SELECT regexp_replace(COALESCE(p_telefon,''), '[^0-9]', '', 'g') AS digit
  ), dinormal AS (
    SELECT CASE
             WHEN digit LIKE '60%' THEN substring(digit from 3)
             WHEN digit LIKE '0%'  THEN substring(digit from 2)
             ELSE digit
           END AS ekor
    FROM input
  )
  SELECT k.id, k.nama, k.telefon, k.alamat, k.lat, k.lng
  FROM kedai k, dinormal d
  WHERE d.ekor <> ''
    AND length(d.ekor) >= 7
    AND regexp_replace(COALESCE(k.telefon,''), '[^0-9]', '', 'g') LIKE '%' || d.ekor
    AND k.status = 'aktif'
  ORDER BY k.nama
  LIMIT 1;
$function$;

GRANT EXECUTE ON FUNCTION public.cari_kedai_ikut_telefon(text) TO anon, authenticated;
