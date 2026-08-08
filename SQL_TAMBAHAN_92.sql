-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 92: Baiki "function_search_path_mutable" pada
-- _auto_revoke_anon_execute() (event trigger yang auto-strip
-- PUBLIC/anon EXECUTE bila fungsi baru dicipta/replace, SQL_TAMBAHAN_67).
-- Sambil di sini: definisi fungsi ni mengesahkan ia SUDAH revoke
-- "FROM PUBLIC, anon" (bukan anon sahaja) sejak awal — sebab 17
-- fungsi lama (SQL_TAMBAHAN_90) masih ada grant PUBLIC ialah kerana
-- ia dicipta SEBELUM trigger ni wujud & tidak pernah di-CREATE OR
-- REPLACE semula sejak itu, bukan kerana trigger tersilap logik.
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public._auto_revoke_anon_execute()
 RETURNS event_trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE obj record;
BEGIN
  FOR obj IN SELECT * FROM pg_event_trigger_ddl_commands() LOOP
    IF obj.object_type = 'function' AND obj.schema_name = 'public' THEN
      BEGIN
        EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon', obj.object_identity);
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'auto_revoke_anon_execute: gagal revoke % — %', obj.object_identity, SQLERRM;
      END;
    END IF;
  END LOOP;
END;
$function$;
