-- ═══════════════════════════════════════════════════════════
--  WAFI TIJARAH TRADING — SQL TAMBAHAN #10
--  Jalankan SEKALI sahaja dalam Supabase SQL Editor.
--  (Baiki padam kedai, diskaun COD, had consignment)
-- ═══════════════════════════════════════════════════════════

-- ═══ Baiki: padam kedai gagal (409) jika ada sejarah transaksi/pre-order ═══
-- Kedai yang dipadam akan set kedai_id kepada NULL pada rekod lama (bukan
-- halang padam) — rekod lama kekal, dipaparkan sebagai destinasi "tidak diketahui".
ALTER TABLE transaksi DROP CONSTRAINT IF EXISTS transaksi_kedai_id_fkey;
ALTER TABLE transaksi ADD CONSTRAINT transaksi_kedai_id_fkey
  FOREIGN KEY (kedai_id) REFERENCES kedai(id) ON DELETE SET NULL;

ALTER TABLE pre_order DROP CONSTRAINT IF EXISTS pre_order_kedai_id_fkey;
ALTER TABLE pre_order ADD CONSTRAINT pre_order_kedai_id_fkey
  FOREIGN KEY (kedai_id) REFERENCES kedai(id) ON DELETE SET NULL;

-- ═══ Diskaun dua peringkat: COD/Tunai + Online Transfer (kedua editable) ═══
ALTER TABLE tetapan ADD COLUMN IF NOT EXISTS diskaun_cod_peratus float DEFAULT 5;

-- ═══ Had Consignment (RM) — hanya pesanan bawah nilai ini dibenarkan consignment ═══
ALTER TABLE tetapan ADD COLUMN IF NOT EXISTS consignment_limit float DEFAULT 300;
