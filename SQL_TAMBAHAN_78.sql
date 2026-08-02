-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 78: Buang overload RPC MATI yang masih ada
-- GRANT EXECUTE anon (audit susulan SQL_TAMBAHAN_66/67).
--
-- Latar: konvensyen projek ini ialah CREATE OR REPLACE FUNCTION
-- utk RPC. Bila parameter baharu ditambah pada RPC sedia ada
-- TANPA DROP overload lama dahulu, Postgres cipta overload BAHARU
-- (signature argumen berbeza) dan bukan ganti — overload lama jadi
-- kod mati yang tak dipanggil client langsung. SQL_TAMBAHAN_77
-- (dan seterusnya) sudah betulkan tabiat ini (DROP dahulu sebelum
-- CREATE OR REPLACE), tapi overload lama yang dicipta SEBELUM
-- trg_auto_revoke_anon_execute wujud (SQL_TAMBAHAN_67) kekal ada
-- GRANT EXECUTE anon peninggalan.
--
-- Disahkan MATI (bukan dipanggil drpd pengurusan.html/index.html/
-- pesan.html — hanya overload TERKINI berikut yang dipanggil):
--   • submit_penghantaran/14-param (dgn p_pekerja_id_override) —
--     dipanggil di pengurusan.html. Overload 8/9/12-param DIBUANG.
--   • cipta_baucar_harian/4-param (p_pekerja_id, p_tarikh, p_jumlah,
--     p_butiran) — dipanggil di pengurusan.html. Overload 2-param
--     (p_pekerja_id, p_tarikh sahaja — versi is_pemilik()-only lama
--     drpd SQL_TAMBAHAN_54, sebelum dilonggarkan di TAMBAHAN_64)
--     DIBUANG.
--
-- TIDAK tereksploitasi sebelum ini — setiap overload yang dibuang
-- ada semakan auth.uid()/is_pemilik() sendiri yang tolak anon
-- dgn betul (auth.uid() = NULL utk anon → EXISTS/is_pemilik() gagal
-- → RAISE EXCEPTION). Ini pembersihan kebersihan/attack-surface,
-- bukan pembetulan kelemahan hidup. Overload LIVE (14-param &
-- 4-param) TIDAK disentuh langsung.
-- ═══════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.submit_penghantaran(text, text, jsonb, double precision, text, text, text, double precision);
DROP FUNCTION IF EXISTS public.submit_penghantaran(text, text, jsonb, double precision, text, text, text, double precision, text);
DROP FUNCTION IF EXISTS public.submit_penghantaran(text, text, jsonb, double precision, text, text, text, double precision, text, text, double precision, double precision);

DROP FUNCTION IF EXISTS public.cipta_baucar_harian(uuid, date);
