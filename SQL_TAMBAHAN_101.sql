-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 101: Mod Susunan Route — Auto / Manual. Pemilik minta:
-- bila kedai terlalu banyak dlm 1 route, susun manual (▲▼ satu-satu,
-- SQL_TAMBAHAN_99) jadi leceh. Tambah ikon toggle "🔀 Auto" / "✋ Manual"
-- per-route:
--   - Manual (asal): kekal route_urutan + butang ▲▼.
--   - Auto (baharu): kedai disusun automatik ikut nearest-neighbour jarak
--     GPS (susunRouteIkutJarak(), pattern sama spt Tab Kedai > Servis) —
--     tiada butang ▲▼ (tak relevan), susunan dikira semula setiap kali
--     dipaparkan (tak perlu simpan route_urutan utk mod ni).
-- ═══════════════════════════════════════════════════════════

ALTER TABLE public.route_kedai
  ADD COLUMN IF NOT EXISTS mod_susunan text NOT NULL DEFAULT 'manual'
    CHECK (mod_susunan IN ('manual','auto'));

CREATE OR REPLACE FUNCTION public.tukar_mod_susunan_route(p_route_id uuid, p_mod text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
BEGIN
  IF NOT is_pemilik() THEN RAISE EXCEPTION 'Hanya pemilik boleh tukar mod susunan route'; END IF;
  IF p_mod NOT IN ('manual','auto') THEN RAISE EXCEPTION 'Mod tidak sah'; END IF;
  UPDATE route_kedai SET mod_susunan = p_mod WHERE id = p_route_id;
END;
$function$;
