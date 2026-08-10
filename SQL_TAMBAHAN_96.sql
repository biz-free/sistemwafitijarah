-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 96: Pemilik minta tukar harga MODAL semua produk
-- supaya markup (untung ÷ modal) jadi TEPAT 20% setiap satu, harga
-- jualan sedia ada KEKAL tidak berubah. Sebelum ini semua 19 produk
-- (aktif & tidak aktif) konsisten 25% markup.
--
-- Formula: harga_beli_baru = harga_jual ÷ 1.20 (bundarkan 2 desimal).
--
-- NOTA PENTING (disahkan kpd pemilik sblm laksana): Laporan Bulanan
-- (Untung Kasar) kira SEMASA — guna stok.harga_beli SEKARANG dikalikan
-- kuantiti sejarah, BUKAN simpan harga modal masa jualan berlaku dulu.
-- Jadi perubahan ni turut kurangkan angka Untung Kasar utk BULAN-BULAN
-- LEPAS (Julai/Ogos 2026) secara retroaktif, bukan cuma jualan akan
-- datang. Pemilik sudah sahkan & pilih teruskan utk SEMUA 19 produk.
-- ═══════════════════════════════════════════════════════════

UPDATE public.stok SET harga_beli = round((harga_jual/1.2)::numeric, 2);
