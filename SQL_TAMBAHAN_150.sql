-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 150: Pemakluman kelulusan pemilik (Telegram) ke kumpulan
-- WhatsApp Team Sales Wafi Tijarah Trading.
--
-- Bila pemilik tekan ✅ Lulus / ✕ Tolak/Batal di Telegram, Edge Function
-- telegram-webhook merekod satu baris di private.pemakluman_kelulusan
-- (melalui rekod_pemakluman_kelulusan). Skrip di VPS (cron, setiap minit)
-- ambil baris belum dihantar melalui ambil_pemakluman_kelulusan(kunci),
-- hantar ke kumpulan WhatsApp, kemudian tandakan dihantar.
--
-- Ikut peraturan: jadual baharu di skema private + RLS hidup (tiada
-- polisi = tiada akses terus); akses hanya melalui fungsi SECURITY DEFINER.
-- Fungsi 'ambil'/'tanda' dilindungi kunci (private.api_kunci), sama seperti
-- laporan_hutang_kedai. Fungsi 'rekod' hanya boleh dipanggil service_role.
-- ═══════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS private.pemakluman_kelulusan (
  id bigserial PRIMARY KEY,
  dicipta timestamptz NOT NULL DEFAULT now(),
  jadual text NOT NULL,
  rekod_id text NOT NULL,
  status text NOT NULL,
  teks text NOT NULL,
  dihantar_pada timestamptz
);
ALTER TABLE private.pemakluman_kelulusan ENABLE ROW LEVEL SECURITY;

-- Dipanggil oleh telegram-webhook (service_role) selepas telegram_putuskan berjaya
CREATE OR REPLACE FUNCTION public.rekod_pemakluman_kelulusan(p_jadual text, p_id text, p_status text, p_teks text)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
  INSERT INTO private.pemakluman_kelulusan (jadual, rekod_id, status, teks)
  VALUES (p_jadual, p_id, p_status, p_teks);
$function$;
REVOKE EXECUTE ON FUNCTION public.rekod_pemakluman_kelulusan(text, text, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rekod_pemakluman_kelulusan(text, text, text, text) TO service_role;

-- Dipanggil skrip VPS: senarai belum dihantar (maks 20, hanya 24 jam terakhir)
CREATE OR REPLACE FUNCTION public.ambil_pemakluman_kelulusan(p_kunci text)
RETURNS TABLE(id bigint, teks text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM private.api_kunci WHERE nama = 'pemakluman_kelulusan_wa' AND kunci = p_kunci) THEN
    RAISE EXCEPTION 'tidak dibenarkan';
  END IF;
  RETURN QUERY
    SELECT p.id, p.teks FROM private.pemakluman_kelulusan p
    WHERE p.dihantar_pada IS NULL AND p.dicipta > now() - interval '24 hours'
    ORDER BY p.id LIMIT 20;
END $function$;

CREATE OR REPLACE FUNCTION public.tanda_pemakluman_dihantar(p_kunci text, p_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM private.api_kunci WHERE nama = 'pemakluman_kelulusan_wa' AND kunci = p_kunci) THEN
    RAISE EXCEPTION 'tidak dibenarkan';
  END IF;
  UPDATE private.pemakluman_kelulusan SET dihantar_pada = now() WHERE id = p_id AND dihantar_pada IS NULL;
END $function$;

REVOKE EXECUTE ON FUNCTION public.ambil_pemakluman_kelulusan(text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.tanda_pemakluman_dihantar(text, bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ambil_pemakluman_kelulusan(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.tanda_pemakluman_dihantar(text, bigint) TO anon, authenticated;

-- Kunci akses baharu (rawak, 48 aksara). Salin nilainya ke VPS (jangan kongsi).
INSERT INTO private.api_kunci (nama, kunci)
SELECT 'pemakluman_kelulusan_wa', replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '')
WHERE NOT EXISTS (SELECT 1 FROM private.api_kunci WHERE nama = 'pemakluman_kelulusan_wa');
