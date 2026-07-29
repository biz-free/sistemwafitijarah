-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 70: Betulkan tetapkan_route_kedai_sendiri (SQL_TAMBAHAN_69)
-- — "column route_id is of type uuid but expression is of type text".
-- kedai.route_id ialah uuid, p_route_id parameter text — PL/pgSQL TIDAK
-- automatik cast text ketara ke uuid (beza drpd literal string terus).
-- Setiap panggilan (assign ATAU unassign/null) gagal serta-merta.
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.tetapkan_route_kedai_sendiri(p_kedai_id text, p_route_id text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Log masuk diperlukan'; END IF;
  UPDATE kedai SET route_id = p_route_id::uuid
    WHERE id = p_kedai_id AND (is_pemilik() OR didaftarkan_oleh = auth.uid());
  IF NOT FOUND THEN RAISE EXCEPTION 'Kedai tidak dijumpai atau anda tiada kebenaran urus route kedai ini'; END IF;
END;
$$;
