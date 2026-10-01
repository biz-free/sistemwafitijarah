-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 157 (SUDAH DIJALANKAN 1 Okt 2026): Naik harga jualan RM1 untuk Tamar Cocoa S001-S004 SAHAJA
-- (bermula 1 Oktober 2026). Produk lain (cth Tamar Coffee Bag) TIDAK diubah.
--
-- Selamat dijalankan SEKALI sahaja: jadual migrasi_sekali menghalang kenaikan
-- berganda jika skrip ini terjalan dua kali.
--
-- LANGKAH DISYORKAN: jalankan SELECT pratonton di bawah dahulu, pastikan hanya
-- produk Tamar Cocoa yang dipilih, baru jalankan blok DO.
--   SELECT id, nama, harga_beli, harga_jual, harga_jual + 1 AS harga_baru
--   FROM stok WHERE id IN ('S001','S002','S003','S004') ORDER BY nama;
-- ═══════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.migrasi_sekali (
  kunci text PRIMARY KEY,
  dijalankan_pada timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.migrasi_sekali ENABLE ROW LEVEL SECURITY; -- tiada polisi = hanya akses server

DO $$
DECLARE v_bil int;
BEGIN
  IF EXISTS (SELECT 1 FROM public.migrasi_sekali WHERE kunci = 'naik_harga_tamar_cocoa_2026_10') THEN
    RAISE NOTICE 'Kenaikan harga Tamar Cocoa sudah dijalankan sebelum ini — dilangkau.';
    RETURN;
  END IF;

  -- Produk S2681163 (Tamar Cocoa Papan Gerai/Kedai Makan, RM1.20) SENGAJA dikecualikan.
  UPDATE public.stok SET harga_jual = harga_jual + 1
   WHERE id IN ('S001','S002','S003','S004') AND nama ILIKE 'Tamar Cocoa%';
  GET DIAGNOSTICS v_bil = ROW_COUNT;

  INSERT INTO public.migrasi_sekali (kunci) VALUES ('naik_harga_tamar_cocoa_2026_10');
  RAISE NOTICE 'Harga dinaikkan RM1 untuk % produk Tamar Cocoa.', v_bil;
END $$;
