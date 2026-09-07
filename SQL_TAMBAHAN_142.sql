-- SQL_TAMBAHAN_142: Paparan Storan Sistem (Live) + Tetapan Arkib Bukti Bayaran
--
-- (a) RPC get_storan_sistem() — pemilik sahaja, pulangkan saiz database (Postgres)
-- + pecahan saiz setiap bucket Supabase Storage, utk papar infografik live dlm
-- Tetapan (elak pekerja/kedai online nampak maklumat infra dalaman).
CREATE OR REPLACE FUNCTION public.get_storan_sistem()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_db_size bigint;
  v_buckets jsonb;
  v_total_storage bigint;
BEGIN
  IF NOT is_pemilik() THEN RAISE EXCEPTION 'Hanya pemilik boleh lihat status storan sistem'; END IF;

  SELECT pg_database_size(current_database()) INTO v_db_size;

  SELECT COALESCE(jsonb_agg(jsonb_build_object('bucket', bucket_id, 'bilangan', bil, 'saiz_bytes', saiz) ORDER BY saiz DESC), '[]'::jsonb),
         COALESCE(SUM(saiz), 0)
    INTO v_buckets, v_total_storage
  FROM (
    SELECT bucket_id, count(*) AS bil, SUM(COALESCE((metadata->>'size')::bigint,0)) AS saiz
    FROM storage.objects GROUP BY bucket_id
  ) x;

  RETURN jsonb_build_object(
    'db_size_bytes', v_db_size,
    'storage_total_bytes', v_total_storage,
    'buckets', v_buckets,
    'dikira_pada', now()
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.get_storan_sistem() TO authenticated;

-- (b) Tetapan Arkib Bukti Bayaran — URL webhook (editable, disimpan tetapan) tempat
-- fail bukti-bayaran lama (>2 bulan, rekod dah SELESAI/disahkan) dihantar sblm
-- dipadam drpd Supabase Storage utk jimat ruang (had FREE tier hampir penuh —
-- lihat siasatan Sep 2026, storan 928MB/1GB).
ALTER TABLE tetapan ADD COLUMN IF NOT EXISTS arkib_webhook_url text;
