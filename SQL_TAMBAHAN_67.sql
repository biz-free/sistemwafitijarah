-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 67: Event trigger — auto-revoke EXECUTE (PUBLIC
-- & anon) pada SETIAP fungsi BAHARU di schema public.
--
-- Susulan penemuan di SQL_TAMBAHAN_66: "ALTER DEFAULT PRIVILEGES
-- ... REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC" (walaupun scoped
-- IN SCHEMA public & FOR ROLE postgres) TIDAK berkesan tutup
-- jurang bagi fungsi akan datang — disahkan guna fungsi ujian
-- sekali pakai selepas jalankan arahan itu, anon masih EXECUTE.
-- Ini isu sedia maklum Supabase (github.com/supabase/supabase
-- issue #43884), bukan silap konfigurasi. Satu-satunya cara
-- benar2 berkesan: event trigger automatik.
--
-- Trigger ini scoped KETAT kepada schema "public" sahaja — tidak
-- sentuh schema dalaman Supabase (auth/storage/extensions/graphql
-- dll), jadi tidak ganggu operasi platform. Dibalut EXCEPTION
-- supaya kegagalan trigger TIDAK PERNAH sekat CREATE FUNCTION
-- akan datang (paling teruk hanya RAISE WARNING).
--
-- Kesan: fungsi BAHARU (dicipta selepas migration ini) di public
-- TIDAK lagi dapat EXECUTE anon/PUBLIC secara automatik — mesti
-- di-GRANT eksplisit selepas CREATE jika ia memang RPC awam
-- (cth. senarai_produk_awam, maklumat_kedai_awam, dll). Fungsi
-- SEDIA ADA (dicipta sebelum migration ini) TIDAK terjejas —
-- event trigger hanya aktif utk DDL akan datang.
--
-- Disahkan LANGSUNG guna fungsi ujian sekali pakai selepas
-- pasang: (1) CREATE FUNCTION biasa tanpa grant eksplisit →
-- anon EXECUTE = false (PUBLIC turut dibuang dari ACL), (2)
-- CREATE FUNCTION diikuti GRANT EXECUTE...TO anon eksplisit →
-- anon EXECUTE = true (aliran kerja utk RPC awam baharu tetap
-- berfungsi). Turut disahkan senarai_produk_awam (RPC awam
-- sedia ada) masih berfungsi utk anon selepas trigger dipasang.
--
-- NOTA: semakan auth.uid() DALAM setiap fungsi kekal pertahanan
-- UTAMA & WAJIB — trigger ini cuma lapisan tambahan supaya silap
-- lupa tulis semakan (spt SQL_TAMBAHAN_64 & 66) gagal selamat
-- (fail-safe) di paras grant, bukan gantian kepada semakan itu.
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public._auto_revoke_anon_execute() RETURNS event_trigger
LANGUAGE plpgsql AS $$
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
$$;

DROP EVENT TRIGGER IF EXISTS trg_auto_revoke_anon_execute;
CREATE EVENT TRIGGER trg_auto_revoke_anon_execute
  ON ddl_command_end
  WHEN TAG IN ('CREATE FUNCTION')
  EXECUTE FUNCTION public._auto_revoke_anon_execute();
