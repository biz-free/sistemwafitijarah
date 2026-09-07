-- SQL_TAMBAHAN_143: Helper get_saiz_fail_storan() — dipanggil edge function
-- arkib-bukti-bayaran SAHAJA (service_role), bukan client — kunci akses ketat
-- (dedah path fail storan dalaman, tak sesuai utk pengguna biasa/pekerja).
CREATE OR REPLACE FUNCTION public.get_saiz_fail_storan(p_bucket text, p_paths text[])
 RETURNS bigint
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE(SUM((metadata->>'size')::bigint), 0)
  FROM storage.objects WHERE bucket_id = p_bucket AND name = ANY(p_paths);
$function$;

REVOKE EXECUTE ON FUNCTION public.get_saiz_fail_storan(text, text[]) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_saiz_fail_storan(text, text[]) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.get_saiz_fail_storan(text, text[]) TO service_role;
