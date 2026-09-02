-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 133: Baiki "Gagal muat senarai produk" di index.html (kedai online)
--
-- PUNCA: SQL_TAMBAHAN_132 buat DROP FUNCTION + CREATE semula pada
-- senarai_produk_awam() (untuk tambah lajur `deskripsi`). Bila fungsi
-- di-DROP, semua GRANT EXECUTE sedia ada turut hilang bersama objek lama —
-- CREATE OR REPLACE biasa akan kekalkan GRANT, tapi DROP+CREATE ni buat
-- OBJEK BAHARU yang mula dengan grant kosong. RPC ni dipanggil oleh SEMUA
-- pelawat awam (belum log masuk) guna role 'anon' utk papar katalog produk
-- di index.html — bila 'anon' tiada kebenaran EXECUTE, panggilan RPC gagal
-- (ditangkap oleh try/catch di initHalaman()) → mesej "Gagal muat senarai
-- produk — sila cuba lagi kemudian" dipaparkan kepada semua pelanggan.
--
-- Nota masa depan: SETIAP kali RPC awam (anon-facing) kena DROP+CREATE
-- (bukan sekadar CREATE OR REPLACE — cth. bila senarai lajur pulangan
-- berubah), WAJIB GRANT EXECUTE semula selepas tu.
-- ═══════════════════════════════════════════════════════════

GRANT EXECUTE ON FUNCTION public.senarai_produk_awam() TO anon;
GRANT EXECUTE ON FUNCTION public.senarai_produk_awam() TO authenticated;
