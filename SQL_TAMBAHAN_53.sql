-- SQL_TAMBAHAN_53: Baiki constraint baucar_bayaran untuk sokong kategori 'upah_harian'
--
-- BUG: cipta_baucar_harian() (SQL_TAMBAHAN_52) gagal dengan ralat
-- "new row for relation baucar_bayaran violates check constraint
-- baucar_bayaran_kategori_check" — jadual asal hanya benarkan kategori
-- 'petrol'/'upah'/'makan', 'upah_harian' tak pernah didaftarkan.
--
-- BUG KEDUA (belum sempat terserlah, dijumpai semasa siasat bug pertama):
-- UNIQUE (pekerja_id, kategori, bulan) direka untuk kategori BULANAN (satu
-- baucar sebulan). 'upah_harian' pula patut SATU baucar SEHARI — guna
-- constraint bulanan yang sama akan sekat baucar harian ke-2 dalam bulan
-- yang sama (pekerja_id+kategori+bulan sama walau tarikh lain). Gantikan
-- dengan 2 index unik terasing: bulanan untuk petrol/upah/makan (kekal
-- macam asal), harian untuk upah_harian (ikut tarikh, bukan bulan).

ALTER TABLE baucar_bayaran DROP CONSTRAINT IF EXISTS baucar_bayaran_kategori_check;
ALTER TABLE baucar_bayaran ADD CONSTRAINT baucar_bayaran_kategori_check
  CHECK (kategori = ANY (ARRAY['petrol'::text, 'upah'::text, 'makan'::text, 'upah_harian'::text]));

ALTER TABLE baucar_bayaran DROP CONSTRAINT IF EXISTS baucar_bayaran_pekerja_id_kategori_bulan_key;
CREATE UNIQUE INDEX IF NOT EXISTS baucar_bayaran_bulanan_unik ON baucar_bayaran (pekerja_id, kategori, bulan)
  WHERE kategori <> 'upah_harian';
CREATE UNIQUE INDEX IF NOT EXISTS baucar_bayaran_harian_unik ON baucar_bayaran (pekerja_id, kategori, tarikh)
  WHERE kategori = 'upah_harian';
