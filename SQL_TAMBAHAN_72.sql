-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 72: Tukar "Padam Produk" kepada nyahaktifkan
-- (soft-delete) — pemadaman kekal (DELETE) pada jadual "stok"
-- SENTIASA gagal untuk mana-mana produk yang pernah bergerak
-- (ada rekod dalam serahan_produk / stok_pekerja / pelupusan_stok,
-- kesemuanya FK "NO ACTION" ke stok.id) — lihat siasatan sebelum
-- ini. Penyelesaian: tambah medan "aktif" (default true), produk
-- "dipadam" cuma ditanda aktif=false, sejarah lama kekal utuh.
--
-- RLS UPDATE sedia ada ("pemilik kemaskini stok") sudah cukup —
-- tiada RPC/polisi baharu diperlukan, cuma medan baharu.
-- ═══════════════════════════════════════════════════════════

ALTER TABLE public.stok ADD COLUMN IF NOT EXISTS aktif boolean NOT NULL DEFAULT true;
