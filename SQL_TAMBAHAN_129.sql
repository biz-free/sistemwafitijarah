-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 129: Mod Paparan Route ("🌐 Semua Kedai" vs "👤 Ikut
-- Pendaftar") — pemilik pilih semasa cipta/urus route sama ada kedai
-- dalam route tu kelihatan kpd SEMUA pekerja di "📍 Perlu Servis", atau
-- HANYA kpd pekerja yg mendaftarkan kedai tersebut (kedai.didaftarkan_oleh).
--
-- Sebelum ni "Perlu Servis" (pekerja) ditapis ikut SEJARAH TRANSAKSI
-- (pernah jual kat kedai tu), tiada kaitan langsung dgn route/pendaftar
-- — pemilik tiada cara kawal secara eksplisit kedai mana pekerja patut
-- nampak. Kini dikawal terus ikut mod paparan route (default 'pendaftar'
-- — lebih ketat/selamat drpd default lama, senang pemilik ubah ke
-- 'semua' bila perlu, cth route dikongsi ramai pekerja).
-- ═══════════════════════════════════════════════════════════

ALTER TABLE route_kedai ADD COLUMN IF NOT EXISTS mod_paparan text DEFAULT 'pendaftar';

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'route_kedai_mod_paparan_check') THEN
    ALTER TABLE route_kedai ADD CONSTRAINT route_kedai_mod_paparan_check
      CHECK (mod_paparan IN ('semua','pendaftar'));
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.tukar_mod_paparan_route(p_route_id uuid, p_mod text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT is_pemilik() THEN RAISE EXCEPTION 'Hanya pemilik boleh tukar mod paparan route'; END IF;
  IF p_mod NOT IN ('semua','pendaftar') THEN RAISE EXCEPTION 'Mod tidak sah'; END IF;
  UPDATE route_kedai SET mod_paparan = p_mod WHERE id = p_route_id;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.tukar_mod_paparan_route(uuid, text) TO authenticated;
