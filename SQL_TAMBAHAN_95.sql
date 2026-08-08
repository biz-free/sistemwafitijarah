-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 95: Betulkan rekod Mutiara BPJ (K8711912) — kedai ni
-- turut layak diskaun 10% bayaran hutang PENUH (spt Mutiara Sg Layar,
-- SQL_TAMBAHAN_94). kedai.hutang sudah ditetapkan ke RM0 oleh pemilik
-- (secara manual, sebelum ciri settlement rasmi wujud) tapi transaksi
-- asal RM960 (01/08/2026) tertinggal masih status 'hutang' — punca
-- Laporan Bulanan Ogos 2026 terlebih kira RM960 (dikesan via trace
-- kedai.hutang vs jumlah transaksi 'hutang' sebenar).
-- ═══════════════════════════════════════════════════════════

UPDATE public.kedai SET diskaun_hutang_peratus = 10 WHERE id = 'K8711912';

-- hutang dah pun RM0 (sedia ada) — cuma clear transaksi lapuk yg tertinggal.
UPDATE public.transaksi SET status = 'selesai' WHERE kedai_id = 'K8711912' AND status = 'hutang';

-- Rekod audit retroaktif (RM960 × 90% = RM864.00 dibayar sebenar).
INSERT INTO public.permohonan_bayaran_hutang
  (id, kedai_id, pekerja_id, jumlah, kaedah_bayaran, nota, settlement_penuh, status, disahkan_oleh, disahkan_pada)
VALUES
  ('PBH-KOREKSI-K8711912', 'K8711912', '7c2af1ae-3808-4e9d-a878-c22c2717e90d', 864.00, 'tunai',
   'Pembetulan rekod: bayaran penuh dgn diskaun 10% (RM960 → RM864.00) — transaksi lapuk dikesan via trace kedai.hutang vs transaksi', true, 'disahkan',
   '7c2af1ae-3808-4e9d-a878-c22c2717e90d', now());
