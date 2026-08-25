-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 115: Optimumkan prestasi dasar RLS (Row Level Security)
-- ikut cadangan RASMI Supabase Performance Advisor.
--
-- Isu 1 — "auth_rls_initplan" (39 dasar merentasi ~40 jadual): dasar RLS
-- yang panggil auth.uid()/auth.role()/is_pemilik() TERUS (tanpa dibalut
-- subquery) menyebabkan Postgres NILAI SEMULA fungsi tu utk SETIAP BARIS
-- yang diimbas, bukan SEKALI sahaja setiap query — walaupun is_pemilik()
-- sendiri sudah ditanda STABLE. Pembalut (select ...) memberi petunjuk
-- kpd query planner utk kira SEKALI (InitPlan) & guna semula hasil utk
-- semua baris — TIADA perubahan logik kebenaran, cuma cara ia dikira.
--
-- Isu 2 — "multiple_permissive_policies" (120 amaran, ~20 jadual): jadual
-- dgn dasar "ALL" (pemilik) + dasar berasingan utk command sama (cth SELECT
-- utk pekerja) menyebabkan KEDUA-DUA dasar dinilai (di-OR) bagi setiap
-- baris. Digabung jadi SATU dasar setiap command yg gabungkan syarat asal
-- dgn OR — secara matematik IDENTIK dgn 2 dasar berasingan (permissive
-- policies memang di-OR), cuma dinilai SEKALI bukan dua kali.
--
-- SEMUA baris di bawah diuji hidup (simulasi sesi pekerja & pemilik sebenar,
-- BEGIN...ROLLBACK) SEBELUM digabung ke migration ni — lihat log perbualan.
-- Tiada perubahan kepada SIAPA boleh akses APA — cuma CARA ia dikira.
-- ═══════════════════════════════════════════════════════════

-- ── affiliate_earnings ──
ALTER POLICY "affiliate lihat pendapatan sendiri, pemilik lihat semua" ON affiliate_earnings
  USING ((affiliate_id = (select auth.uid())) OR (select is_pemilik()));

-- ── affiliate_payout ──
ALTER POLICY "affiliate lihat & mohon bayaran sendiri, pemilik lihat semua" ON affiliate_payout
  USING ((affiliate_id = (select auth.uid())) OR (select is_pemilik()));

-- ── affiliates ──
ALTER POLICY "pengguna mohon jadi affiliate sendiri" ON affiliates
  WITH CHECK (id = (select auth.uid()));
ALTER POLICY "affiliate lihat sendiri, pemilik lihat semua" ON affiliates
  USING ((id = (select auth.uid())) OR (select is_pemilik()));
ALTER POLICY "pemilik urus semua affiliate" ON affiliates
  USING ((select is_pemilik()));

-- ── alamat_pelanggan ──
ALTER POLICY "pelanggan urus alamat sendiri" ON alamat_pelanggan
  USING ((select auth.uid()) = auth_uid) WITH CHECK ((select auth.uid()) = auth_uid);

-- ── baucar ──
ALTER POLICY "pemilik urus baucar" ON baucar
  USING ((select is_pemilik()));

-- ── baucar_bayaran ──
ALTER POLICY "pemilik urus semua baucar" ON baucar_bayaran
  USING ((select is_pemilik())) WITH CHECK ((select is_pemilik()));
ALTER POLICY "pemilik padam baucar bayaran" ON baucar_bayaran
  USING ((select is_pemilik()));
ALTER POLICY "pekerja baca baucar sendiri" ON baucar_bayaran
  USING (pekerja_id = (select auth.uid()));

-- ── baucar_guna ──
ALTER POLICY "pemilik padam baucar_guna" ON baucar_guna
  USING ((select is_pemilik()));
ALTER POLICY "pemilik baca baucar_guna" ON baucar_guna
  USING ((select is_pemilik()));

-- ── bonus_kedai_baru ── (gabung "urus semua" ALL + "lihat sendiri" SELECT jadi 1 SELECT)
DROP POLICY IF EXISTS "staff lihat bonus kedai sendiri" ON bonus_kedai_baru;
ALTER POLICY "pemilik urus semua bonus kedai" ON bonus_kedai_baru
  USING ((select is_pemilik()));
CREATE POLICY "staff lihat bonus kedai sendiri" ON bonus_kedai_baru FOR SELECT
  USING ((pekerja_id = (select auth.uid())) OR (select is_pemilik()));

-- ── gps_track ── (gabung "baca gps sendiri" + "baca semua gps" jadi 1 SELECT)
DROP POLICY IF EXISTS "pekerja baca gps sendiri" ON gps_track;
DROP POLICY IF EXISTS "pemilik baca semua gps" ON gps_track;
CREATE POLICY "baca gps sendiri atau semua (pemilik)" ON gps_track FOR SELECT
  USING ((pekerja_id = (select auth.uid())) OR (select is_pemilik()));
ALTER POLICY "pekerja tambah gps sendiri" ON gps_track
  WITH CHECK (pekerja_id = (select auth.uid()));

-- ── kategori_stok ── (gabung "urus kategori" ALL + "baca kategori" SELECT jadi 1 SELECT)
DROP POLICY IF EXISTS "staff boleh baca kategori" ON kategori_stok;
ALTER POLICY "pemilik urus kategori" ON kategori_stok
  USING ((select is_pemilik())) WITH CHECK ((select is_pemilik()));
CREATE POLICY "staff boleh baca kategori" ON kategori_stok FOR SELECT
  USING ((select is_pemilik()) OR EXISTS (SELECT 1 FROM profiles WHERE profiles.id = (select auth.uid())));

-- ── kedai ──
ALTER POLICY "pemilik padam kedai" ON kedai
  USING ((select is_pemilik()));
ALTER POLICY "staff tambah kedai" ON kedai
  WITH CHECK ((select auth.role()) = 'authenticated'::text);
ALTER POLICY "baca kedai" ON kedai
  USING ((select auth.role()) = 'authenticated'::text);
ALTER POLICY "pemilik kemaskini kedai" ON kedai
  USING (EXISTS (SELECT 1 FROM profiles WHERE profiles.id = (select auth.uid()) AND profiles.role = 'pemilik'::text));

-- ── kehadiran ── (gabung "urus sendiri" ALL + "baca semua" SELECT jadi 1 SELECT explicit)
DROP POLICY IF EXISTS "pemilik baca semua kehadiran" ON kehadiran;
ALTER POLICY "pekerja urus kehadiran sendiri" ON kehadiran
  USING (pekerja_id = (select auth.uid())) WITH CHECK (pekerja_id = (select auth.uid()));
ALTER POLICY "pemilik padam kehadiran" ON kehadiran
  USING ((select is_pemilik()));
CREATE POLICY "pemilik baca semua kehadiran" ON kehadiran FOR SELECT
  USING ((select is_pemilik()));

-- ── kunjungan_web ──
ALTER POLICY "pemilik boleh baca kunjungan" ON kunjungan_web
  USING ((select is_pemilik()));

-- ── pelupusan_stok ── (gabung serupa gps_track/kehadiran)
DROP POLICY IF EXISTS "pemilik baca semua pelupusan" ON pelupusan_stok;
ALTER POLICY "pekerja urus pelupusan sendiri" ON pelupusan_stok
  USING (pekerja_id = (select auth.uid())) WITH CHECK (pekerja_id = (select auth.uid()));
ALTER POLICY "pemilik padam pelupusan" ON pelupusan_stok
  USING ((select is_pemilik()));
CREATE POLICY "pemilik baca semua pelupusan" ON pelupusan_stok FOR SELECT
  USING ((select is_pemilik()));

-- ── pemohon_program ──
ALTER POLICY "pemilik boleh padam permohonan" ON pemohon_program
  USING ((select is_pemilik()));
ALTER POLICY "staff boleh baca permohonan" ON pemohon_program
  USING (EXISTS (SELECT 1 FROM profiles WHERE profiles.id = (select auth.uid())));
ALTER POLICY "staff boleh kemaskini permohonan" ON pemohon_program
  USING (EXISTS (SELECT 1 FROM profiles WHERE profiles.id = (select auth.uid())));

-- ── penugasan_route_harian ── (gabung serupa)
DROP POLICY IF EXISTS "pekerja lihat penugasan sendiri" ON penugasan_route_harian;
ALTER POLICY "pemilik urus semua penugasan" ON penugasan_route_harian
  USING ((select is_pemilik())) WITH CHECK ((select is_pemilik()));
CREATE POLICY "pekerja lihat penugasan sendiri" ON penugasan_route_harian FOR SELECT
  USING ((pekerja_id = (select auth.uid())) OR (select is_pemilik()));

-- ── permohonan_bayaran_hutang ──
ALTER POLICY "pekerja hantar permohonan bayaran sendiri" ON permohonan_bayaran_hutang
  WITH CHECK (pekerja_id = (select auth.uid()));
ALTER POLICY "staff lihat permohonan bayaran" ON permohonan_bayaran_hutang
  USING ((pekerja_id = (select auth.uid())) OR (select is_pemilik()));
ALTER POLICY "pemilik urus semua permohonan bayaran" ON permohonan_bayaran_hutang
  USING ((select is_pemilik()));

-- ── permohonan_cuti ── (gabung serupa)
DROP POLICY IF EXISTS "pemilik baca semua permohonan" ON permohonan_cuti;
ALTER POLICY "pekerja urus permohonan sendiri" ON permohonan_cuti
  USING (pekerja_id = (select auth.uid())) WITH CHECK (pekerja_id = (select auth.uid()));
ALTER POLICY "pemilik padam permohonan_cuti" ON permohonan_cuti
  USING ((select is_pemilik()));
ALTER POLICY "pemilik kelulusan permohonan" ON permohonan_cuti
  USING ((select is_pemilik()));
CREATE POLICY "pemilik baca semua permohonan" ON permohonan_cuti FOR SELECT
  USING ((select is_pemilik()));

-- ── permohonan_padam ──
ALTER POLICY "pemilik padam permohonan padam" ON permohonan_padam
  USING ((select is_pemilik()));
ALTER POLICY "pekerja hantar permohonan padam" ON permohonan_padam
  WITH CHECK ((select auth.uid()) = pekerja_id);
ALTER POLICY "staff baca permohonan padam" ON permohonan_padam
  USING ((select is_pemilik()) OR (pekerja_id = (select auth.uid())));
ALTER POLICY "pemilik putuskan permohonan padam" ON permohonan_padam
  USING ((select is_pemilik())) WITH CHECK ((select is_pemilik()));

-- ── pesanan_edagang ── (gabung 3 dasar SELECT jadi 1)
DROP POLICY IF EXISTS "pekerja baca pesanan edagang ditugaskan" ON pesanan_edagang;
DROP POLICY IF EXISTS "pelanggan boleh baca pesanan sendiri" ON pesanan_edagang;
DROP POLICY IF EXISTS "pemilik baca semua pesanan edagang" ON pesanan_edagang;
CREATE POLICY "baca pesanan edagang (ditugaskan/sendiri/pemilik)" ON pesanan_edagang FOR SELECT
  USING (
    (assigned_pekerja_id = (select auth.uid()))
    OR (((select auth.uid()) IS NOT NULL) AND ((select auth.uid()) = auth_uid))
    OR (select is_pemilik())
  );
ALTER POLICY "pemilik boleh padam pesanan" ON pesanan_edagang
  USING ((select is_pemilik()));
-- Gabung 2 dasar UPDATE jadi 1
DROP POLICY IF EXISTS "pekerja kemaskini pesanan edagang ditugaskan" ON pesanan_edagang;
DROP POLICY IF EXISTS "pemilik kemaskini semua pesanan edagang" ON pesanan_edagang;
CREATE POLICY "kemaskini pesanan edagang (ditugaskan/pemilik)" ON pesanan_edagang FOR UPDATE
  USING ((assigned_pekerja_id = (select auth.uid())) OR (select is_pemilik()))
  WITH CHECK ((assigned_pekerja_id = (select auth.uid())) OR (select is_pemilik()));

-- ── pre_order ──
ALTER POLICY "pemilik padam pre_order" ON pre_order
  USING ((select is_pemilik()));
ALTER POLICY "staff boleh baca pre-order" ON pre_order
  USING (
    (select is_pemilik())
    OR (
      EXISTS (SELECT 1 FROM profiles WHERE profiles.id = (select auth.uid()))
      AND ((assigned_pekerja_id IS NULL) OR (assigned_pekerja_id = (select auth.uid())))
    )
  );
ALTER POLICY "staff boleh kemaskini pre-order" ON pre_order
  USING ((select auth.role()) = 'authenticated'::text);

-- ── profiles ── (gabung "boleh baca semua" + "profil sendiri" jadi 1 SELECT)
DROP POLICY IF EXISTS "profil sendiri" ON profiles;
ALTER POLICY "pemilik padam profil pekerja" ON profiles
  USING ((select is_pemilik()));
ALTER POLICY "pemilik boleh daftar profil pekerja" ON profiles
  WITH CHECK ((select is_pemilik()));
ALTER POLICY "pemilik boleh baca semua profil" ON profiles
  USING ((select is_pemilik()));
CREATE POLICY "profil sendiri" ON profiles FOR SELECT
  USING (((select auth.uid()) = id) OR (select is_pemilik()));

-- ── push_subscriptions ──
ALTER POLICY "pengguna urus langganan push sendiri" ON push_subscriptions
  USING (user_id = (select auth.uid()));

-- ── route_kedai ── (gabung "urus route" ALL + "baca route" SELECT jadi 1 SELECT)
DROP POLICY IF EXISTS "staff boleh baca route" ON route_kedai;
ALTER POLICY "pemilik urus route" ON route_kedai
  USING ((select is_pemilik())) WITH CHECK ((select is_pemilik()));
CREATE POLICY "staff boleh baca route" ON route_kedai FOR SELECT
  USING ((select is_pemilik()) OR EXISTS (SELECT 1 FROM profiles WHERE profiles.id = (select auth.uid())));

-- ── rujukan_ganjaran ──
ALTER POLICY "pemilik baca rujukan_ganjaran" ON rujukan_ganjaran
  USING ((select is_pemilik()));

-- ── rujukan_manual ──
ALTER POLICY "pemilik urus rujukan_manual" ON rujukan_manual
  USING ((select is_pemilik())) WITH CHECK ((select is_pemilik()));

-- ── serahan_cash ──
ALTER POLICY "pemilik padam serahan cash" ON serahan_cash
  USING ((select is_pemilik()));
ALTER POLICY "pekerja hantar serahan cash sendiri" ON serahan_cash
  WITH CHECK (pekerja_id = (select auth.uid()));
ALTER POLICY "staff lihat serahan cash" ON serahan_cash
  USING ((pekerja_id = (select auth.uid())) OR (select is_pemilik()));
ALTER POLICY "pemilik sahkan serahan cash" ON serahan_cash
  USING ((select is_pemilik()));

-- ── serahan_produk ── (gabung "urus semua" ALL + "lihat" SELECT jadi 1 SELECT)
DROP POLICY IF EXISTS "staff lihat serahan produk" ON serahan_produk;
ALTER POLICY "pemilik urus semua serahan produk" ON serahan_produk
  USING ((select is_pemilik()));
CREATE POLICY "staff lihat serahan produk" ON serahan_produk FOR SELECT
  USING ((pekerja_id = (select auth.uid())) OR (select is_pemilik()));

-- ── stok ──
ALTER POLICY "pemilik padam stok" ON stok
  USING ((select is_pemilik()));
ALTER POLICY "pemilik tambah stok" ON stok
  WITH CHECK (EXISTS (SELECT 1 FROM profiles WHERE profiles.id = (select auth.uid()) AND profiles.role = 'pemilik'::text));
ALTER POLICY "baca stok" ON stok
  USING ((select auth.role()) = 'authenticated'::text);
ALTER POLICY "pemilik kemaskini stok" ON stok
  USING (EXISTS (SELECT 1 FROM profiles WHERE profiles.id = (select auth.uid()) AND profiles.role = 'pemilik'::text));

-- ── stok_pekerja ──
ALTER POLICY "pemilik padam stok_pekerja" ON stok_pekerja
  USING ((select is_pemilik()));
ALTER POLICY "pekerja baca stok sendiri" ON stok_pekerja
  USING ((pekerja_id = (select auth.uid())) OR (select is_pemilik()));

-- ── tetapan ──
ALTER POLICY "pemilik boleh kemaskini tetapan" ON tetapan
  USING ((select is_pemilik()));

-- ── transaksi ──
ALTER POLICY "pemilik padam transaksi" ON transaksi
  USING ((select is_pemilik()));
ALTER POLICY "baca transaksi" ON transaksi
  USING ((select auth.role()) = 'authenticated'::text);

-- ── wa_hebahan_batch / wa_hebahan_state ──
ALTER POLICY "pemilik urus wa_hebahan_batch" ON wa_hebahan_batch
  USING ((select is_pemilik())) WITH CHECK ((select is_pemilik()));
ALTER POLICY "pemilik urus wa_hebahan_state" ON wa_hebahan_state
  USING ((select is_pemilik())) WITH CHECK ((select is_pemilik()));

-- ── winback_log ──
ALTER POLICY "pemilik baca winback_log" ON winback_log
  USING ((select is_pemilik()));

-- ── zon_penghantaran ──
ALTER POLICY "pemilik urus zon" ON zon_penghantaran
  USING ((select is_pemilik()));

-- ── Indeks pada foreign key yg kerap digunakan dlm dasar RLS/carian
-- (fokus jadual bervolum tinggi/kerap disoal — bukan kesemua 41 amaran,
-- yg bervolum rendah/jarang JOIN tak beri manfaat sepadan dgn overhead
-- tulis tambahan). ──
CREATE INDEX IF NOT EXISTS idx_transaksi_kedai_id ON transaksi(kedai_id);
CREATE INDEX IF NOT EXISTS idx_gps_track_pekerja_id ON gps_track(pekerja_id);
CREATE INDEX IF NOT EXISTS idx_gps_track_kehadiran_id ON gps_track(kehadiran_id);
CREATE INDEX IF NOT EXISTS idx_kehadiran_pekerja_id ON kehadiran(pekerja_id);
CREATE INDEX IF NOT EXISTS idx_serahan_produk_pekerja_id ON serahan_produk(pekerja_id);
CREATE INDEX IF NOT EXISTS idx_pesanan_edagang_assigned_pekerja_id ON pesanan_edagang(assigned_pekerja_id);
CREATE INDEX IF NOT EXISTS idx_pre_order_kedai_id ON pre_order(kedai_id);
CREATE INDEX IF NOT EXISTS idx_pelupusan_stok_kedai_id ON pelupusan_stok(kedai_id);
