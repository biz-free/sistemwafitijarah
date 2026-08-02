-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 81: Baiki "Gagal padam: new row for relation
-- serahan_produk violates check constraint" di Padam Transaksi Kedai.
--
-- PUNCA: SQL_TAMBAHAN_79 tambah INSERT INTO serahan_produk dengan
-- jenis='padam_pulang' utk audit trail, tapi CHECK constraint
-- serahan_produk_jenis_check sedia ada cuma benarkan nilai
-- 'baik','reject','ambil','pindah_keluar','pindah_masuk','restock'
-- — 'padam_pulang' bukan ahli senarai tu, jadi INSERT ditolak dan
-- keseluruhan padam_transaksi_kedai() gagal (rollback), transaksi
-- terus tak boleh dipadam langsung.
--
-- FIX: Longgarkan CHECK constraint utk turut benarkan 'padam_pulang'.
-- ═══════════════════════════════════════════════════════════

ALTER TABLE public.serahan_produk DROP CONSTRAINT serahan_produk_jenis_check;
ALTER TABLE public.serahan_produk ADD CONSTRAINT serahan_produk_jenis_check
  CHECK (jenis = ANY (ARRAY['baik','reject','ambil','pindah_keluar','pindah_masuk','restock','padam_pulang']));
