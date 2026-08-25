-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 117: Cadangan prestasi tambahan
-- (sambungan SQL_TAMBAHAN_115/116)
--
-- 1. Indeks pada 33 foreign key yang masih tiada liputan indeks
--    (amaran "unindexed_foreign_keys" drpd Supabase Performance Advisor).
-- 2. Dasar arkib/retention utk jadual `gps_track` — jadual ni cuma titik
--    GPS SEMENTARA sepanjang syif (bukan rekod kehadiran rasmi, yg
--    disimpan berasingan dlm `kehadiran`), jadi selamat dipangkas lepas
--    90 hari. Cron harian, jam 2 pagi waktu Malaysia (18:00 UTC).
-- ═══════════════════════════════════════════════════════════

-- ── Indeks foreign key ──
CREATE INDEX IF NOT EXISTS idx_affiliate_payout_affiliate_id ON affiliate_payout(affiliate_id);
CREATE INDEX IF NOT EXISTS idx_affiliate_payout_disahkan_oleh ON affiliate_payout(disahkan_oleh);
CREATE INDEX IF NOT EXISTS idx_affiliates_disahkan_oleh ON affiliates(disahkan_oleh);
CREATE INDEX IF NOT EXISTS idx_alamat_pelanggan_auth_uid ON alamat_pelanggan(auth_uid);
CREATE INDEX IF NOT EXISTS idx_baucar_bayaran_diluluskan_oleh ON baucar_bayaran(diluluskan_oleh);
CREATE INDEX IF NOT EXISTS idx_baucar_guna_pesanan_id ON baucar_guna(pesanan_id);
CREATE INDEX IF NOT EXISTS idx_bonus_kedai_baru_baucar_id ON bonus_kedai_baru(baucar_id);
CREATE INDEX IF NOT EXISTS idx_bonus_kedai_baru_kedai_id ON bonus_kedai_baru(kedai_id);
CREATE INDEX IF NOT EXISTS idx_bonus_kedai_baru_pekerja_id ON bonus_kedai_baru(pekerja_id);
CREATE INDEX IF NOT EXISTS idx_kedai_didaftarkan_oleh ON kedai(didaftarkan_oleh);
CREATE INDEX IF NOT EXISTS idx_kedai_route_id ON kedai(route_id);
CREATE INDEX IF NOT EXISTS idx_pelupusan_stok_pekerja_id ON pelupusan_stok(pekerja_id);
CREATE INDEX IF NOT EXISTS idx_pelupusan_stok_stok_id ON pelupusan_stok(stok_id);
CREATE INDEX IF NOT EXISTS idx_penugasan_route_harian_created_by ON penugasan_route_harian(created_by);
CREATE INDEX IF NOT EXISTS idx_penugasan_route_harian_pekerja_id ON penugasan_route_harian(pekerja_id);
CREATE INDEX IF NOT EXISTS idx_penugasan_route_harian_route_id ON penugasan_route_harian(route_id);
CREATE INDEX IF NOT EXISTS idx_permohonan_bayaran_hutang_disahkan_oleh ON permohonan_bayaran_hutang(disahkan_oleh);
CREATE INDEX IF NOT EXISTS idx_permohonan_bayaran_hutang_kedai_id ON permohonan_bayaran_hutang(kedai_id);
CREATE INDEX IF NOT EXISTS idx_permohonan_bayaran_hutang_pekerja_id ON permohonan_bayaran_hutang(pekerja_id);
CREATE INDEX IF NOT EXISTS idx_permohonan_cuti_pekerja_id ON permohonan_cuti(pekerja_id);
CREATE INDEX IF NOT EXISTS idx_permohonan_padam_diputuskan_oleh ON permohonan_padam(diputuskan_oleh);
CREATE INDEX IF NOT EXISTS idx_permohonan_padam_pekerja_id ON permohonan_padam(pekerja_id);
CREATE INDEX IF NOT EXISTS idx_pesanan_edagang_auth_uid ON pesanan_edagang(auth_uid);
CREATE INDEX IF NOT EXISTS idx_pesanan_edagang_zon_penghantaran ON pesanan_edagang(zon_penghantaran);
CREATE INDEX IF NOT EXISTS idx_pre_order_assigned_pekerja_id ON pre_order(assigned_pekerja_id);
CREATE INDEX IF NOT EXISTS idx_serahan_cash_disahkan_oleh ON serahan_cash(disahkan_oleh);
CREATE INDEX IF NOT EXISTS idx_serahan_cash_pekerja_id ON serahan_cash(pekerja_id);
CREATE INDEX IF NOT EXISTS idx_serahan_produk_disahkan_oleh ON serahan_produk(disahkan_oleh);
CREATE INDEX IF NOT EXISTS idx_serahan_produk_rujuk_pekerja_id ON serahan_produk(rujuk_pekerja_id);
CREATE INDEX IF NOT EXISTS idx_serahan_produk_stok_id ON serahan_produk(stok_id);
CREATE INDEX IF NOT EXISTS idx_stok_pekerja_stok_id ON stok_pekerja(stok_id);
CREATE INDEX IF NOT EXISTS idx_transaksi_disahkan_oleh ON transaksi(disahkan_oleh);
CREATE INDEX IF NOT EXISTS idx_transaksi_jumlah_diedit_oleh ON transaksi(jumlah_diedit_oleh);

-- ── Retention gps_track (>90 hari) ──
CREATE OR REPLACE FUNCTION public.padam_gps_track_lama()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM gps_track WHERE created_at < (now() - interval '90 days');
END;
$$;

SELECT cron.schedule(
  'padam-gps-track-lama-harian',
  '0 18 * * *',
  $$SELECT public.padam_gps_track_lama();$$
);
