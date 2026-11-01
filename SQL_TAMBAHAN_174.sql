-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 174: Butang "✅ Dah Lawat" (Tab Kedai > 📍 Perlu Servis)
-- Tandakan kedai sudah dilawat tanpa perlu rekod transaksi — kemas kini
-- kedai.last_visit sahaja. RLS `kedai` UPDATE cuma benarkan pemilik, jadi
-- guna RPC SECURITY DEFINER supaya pekerja pun boleh. Tiada jadual baharu.
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.tandakan_dah_lawat(p_kedai_id text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Log masuk diperlukan';
  END IF;

  UPDATE kedai SET last_visit = CURRENT_DATE::text WHERE id = p_kedai_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Kedai tidak dijumpai';
  END IF;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.tandakan_dah_lawat(text) TO authenticated;
