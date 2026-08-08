-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 91: BETULKAN kesilapan SQL_TAMBAHAN_90 — REVOKE
-- FROM anon sahaja TIDAK MENCUKUPI. Semua 17 fungsi tu turut ada
-- grant kepada pseudo-role PUBLIC (default PostgreSQL bila fungsi
-- dicipta), dan grant PUBLIC terpakai kepada SEMUA role termasuk
-- anon — jadi anon MASIH boleh panggil terus walaupun grant
-- eksplisitnya sudah dibuang. Disahkan via get_advisors(security):
-- papan_jualan_pekerja_hari_ini (kebocoran data yang sepatutnya
-- dah settle) masih tersenarai dalam anon_security_definer_
-- function_executable selepas SQL_TAMBAHAN_90 diguna pakai.
--
-- Fix: REVOKE EXECUTE ... FROM PUBLIC juga. Grant eksplisit kepada
-- authenticated/postgres/service_role KEKAL tidak tersentuh (REVOKE
-- hanya buang privilege bagi grantee yang dinyatakan).
-- ═══════════════════════════════════════════════════════════

REVOKE EXECUTE ON FUNCTION public.papan_jualan_pekerja_hari_ini() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.easyparcel_status() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.lepas_promosi_pesanan_gagal() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.lepaskan_preorder_lapuk() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.cipta_baucar_bayaran(uuid, text, text, double precision, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.cipta_baucar_harian(uuid, date, double precision, jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.hantar_permohonan_cuti(text, text, date, date, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.kemaskini_profil_sendiri(text, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.pindah_stok_pekerja(uuid, uuid, text, integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.pulang_stok_pekerja(text, integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.putuskan_ambil_stok(text, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.putuskan_serahan_produk(text, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.rekod_bayaran(text, double precision) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.restock_produk(text, integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sahkan_jualan_konsainan(text, jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.serah_produk_reject(text, text, integer, text, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.tugaskan_preorder(text, uuid) FROM PUBLIC;
