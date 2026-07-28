-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 69: Pekerja boleh urus route untuk kedai SENDIRI
-- sahaja (yang mereka daftarkan) — RLS "kedai" UPDATE kekal
-- pemilik-only (elak pekerja edit medan lain macam nama/hutang/
-- status), jadi RPC khas ni HANYA dedahkan medan route_id.
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.tetapkan_route_kedai_sendiri(p_kedai_id text, p_route_id text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Log masuk diperlukan'; END IF;
  UPDATE kedai SET route_id = p_route_id
    WHERE id = p_kedai_id AND (is_pemilik() OR didaftarkan_oleh = auth.uid());
  IF NOT FOUND THEN RAISE EXCEPTION 'Kedai tidak dijumpai atau anda tiada kebenaran urus route kedai ini'; END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.tetapkan_route_kedai_sendiri(text, text) TO authenticated;
