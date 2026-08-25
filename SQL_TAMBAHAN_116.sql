-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 116: Selesaikan baki amaran "multiple_permissive_policies"
-- (sambungan SQL_TAMBAHAN_115).
--
-- Punca: dasar RLS berskop "ALL" (cth "pemilik urus semua X") turut
-- terpakai pada SELECT — jadi bila jadual yg sama ada dasar SELECT lain
-- (cth "pekerja lihat X sendiri"), KEDUA-DUA dinilai (di-OR) setiap kali,
-- walaupun salah satu (ALL) sudah tidak perlu utk SELECT.
--
-- Pembetulan: pisahkan dasar "ALL" kepada dasar INSERT/UPDATE/DELETE
-- eksplisit sahaja (buang liputan SELECT-nya), dan pastikan mana-mana
-- syarat SELECT/UPDATE/DELETE pekerja-sendiri yg asalnya datang drpd
-- dasar ALL itu digabung (OR) ke dasar sedia ada supaya TIADA capaian
-- hilang. Diuji hidup selepas apply.
-- ═══════════════════════════════════════════════════════════

-- ── baucar ──
DROP POLICY "pemilik urus baucar" ON baucar;
CREATE POLICY "pemilik tambah baucar" ON baucar FOR INSERT WITH CHECK ((select is_pemilik()));
CREATE POLICY "pemilik kemaskini baucar" ON baucar FOR UPDATE USING ((select is_pemilik()));
CREATE POLICY "pemilik padam baucar" ON baucar FOR DELETE USING ((select is_pemilik()));
ALTER POLICY "semua boleh baca baucar aktif" ON baucar USING ((aktif = true) OR (select is_pemilik()));

-- ── baucar_bayaran ──
DROP POLICY "pemilik urus semua baucar" ON baucar_bayaran;
CREATE POLICY "pemilik tambah baucar bayaran" ON baucar_bayaran FOR INSERT WITH CHECK ((select is_pemilik()));
CREATE POLICY "pemilik kemaskini baucar bayaran" ON baucar_bayaran FOR UPDATE USING ((select is_pemilik())) WITH CHECK ((select is_pemilik()));
ALTER POLICY "pekerja baca baucar sendiri" ON baucar_bayaran USING ((pekerja_id = (select auth.uid())) OR (select is_pemilik()));

-- ── bonus_kedai_baru ──
DROP POLICY "pemilik urus semua bonus kedai" ON bonus_kedai_baru;
CREATE POLICY "pemilik tambah bonus kedai" ON bonus_kedai_baru FOR INSERT WITH CHECK ((select is_pemilik()));
CREATE POLICY "pemilik kemaskini bonus kedai" ON bonus_kedai_baru FOR UPDATE USING ((select is_pemilik()));
CREATE POLICY "pemilik padam bonus kedai" ON bonus_kedai_baru FOR DELETE USING ((select is_pemilik()));

-- ── kategori_stok ──
DROP POLICY "pemilik urus kategori" ON kategori_stok;
CREATE POLICY "pemilik tambah kategori" ON kategori_stok FOR INSERT WITH CHECK ((select is_pemilik()));
CREATE POLICY "pemilik kemaskini kategori" ON kategori_stok FOR UPDATE USING ((select is_pemilik())) WITH CHECK ((select is_pemilik()));
CREATE POLICY "pemilik padam kategori" ON kategori_stok FOR DELETE USING ((select is_pemilik()));

-- ── kehadiran ──
DROP POLICY "pekerja urus kehadiran sendiri" ON kehadiran;
CREATE POLICY "pekerja tambah kehadiran sendiri" ON kehadiran FOR INSERT WITH CHECK (pekerja_id = (select auth.uid()));
CREATE POLICY "pekerja kemaskini kehadiran sendiri" ON kehadiran FOR UPDATE USING (pekerja_id = (select auth.uid())) WITH CHECK (pekerja_id = (select auth.uid()));
ALTER POLICY "pemilik padam kehadiran" ON kehadiran USING ((pekerja_id = (select auth.uid())) OR (select is_pemilik()));
ALTER POLICY "pemilik baca semua kehadiran" ON kehadiran USING ((pekerja_id = (select auth.uid())) OR (select is_pemilik()));

-- ── pelupusan_stok ──
DROP POLICY "pekerja urus pelupusan sendiri" ON pelupusan_stok;
CREATE POLICY "pekerja tambah pelupusan sendiri" ON pelupusan_stok FOR INSERT WITH CHECK (pekerja_id = (select auth.uid()));
CREATE POLICY "pekerja kemaskini pelupusan sendiri" ON pelupusan_stok FOR UPDATE USING (pekerja_id = (select auth.uid())) WITH CHECK (pekerja_id = (select auth.uid()));
ALTER POLICY "pemilik padam pelupusan" ON pelupusan_stok USING ((pekerja_id = (select auth.uid())) OR (select is_pemilik()));
ALTER POLICY "pemilik baca semua pelupusan" ON pelupusan_stok USING ((pekerja_id = (select auth.uid())) OR (select is_pemilik()));

-- ── penugasan_route_harian ──
DROP POLICY "pemilik urus semua penugasan" ON penugasan_route_harian;
CREATE POLICY "pemilik tambah penugasan" ON penugasan_route_harian FOR INSERT WITH CHECK ((select is_pemilik()));
CREATE POLICY "pemilik kemaskini penugasan" ON penugasan_route_harian FOR UPDATE USING ((select is_pemilik())) WITH CHECK ((select is_pemilik()));
CREATE POLICY "pemilik padam penugasan" ON penugasan_route_harian FOR DELETE USING ((select is_pemilik()));

-- ── permohonan_cuti ──
DROP POLICY "pekerja urus permohonan sendiri" ON permohonan_cuti;
CREATE POLICY "pekerja hantar permohonan cuti sendiri" ON permohonan_cuti FOR INSERT WITH CHECK (pekerja_id = (select auth.uid()));
ALTER POLICY "pemilik padam permohonan_cuti" ON permohonan_cuti USING ((pekerja_id = (select auth.uid())) OR (select is_pemilik()));
ALTER POLICY "pemilik baca semua permohonan" ON permohonan_cuti USING ((pekerja_id = (select auth.uid())) OR (select is_pemilik()));
ALTER POLICY "pemilik kelulusan permohonan" ON permohonan_cuti USING ((pekerja_id = (select auth.uid())) OR (select is_pemilik()));

-- ── profiles (dasar "pemilik boleh baca semua profil" berlebihan, sudah
-- diliputi sepenuhnya oleh "profil sendiri" yg kini termasuk OR is_pemilik()) ──
DROP POLICY "pemilik boleh baca semua profil" ON profiles;

-- ── route_kedai ──
DROP POLICY "pemilik urus route" ON route_kedai;
CREATE POLICY "pemilik tambah route" ON route_kedai FOR INSERT WITH CHECK ((select is_pemilik()));
CREATE POLICY "pemilik kemaskini route" ON route_kedai FOR UPDATE USING ((select is_pemilik())) WITH CHECK ((select is_pemilik()));
CREATE POLICY "pemilik padam route" ON route_kedai FOR DELETE USING ((select is_pemilik()));

-- ── serahan_produk ──
DROP POLICY "pemilik urus semua serahan produk" ON serahan_produk;
CREATE POLICY "pemilik tambah serahan produk" ON serahan_produk FOR INSERT WITH CHECK ((select is_pemilik()));
CREATE POLICY "pemilik kemaskini serahan produk" ON serahan_produk FOR UPDATE USING ((select is_pemilik()));
CREATE POLICY "pemilik padam serahan produk" ON serahan_produk FOR DELETE USING ((select is_pemilik()));

-- ── zon_penghantaran ──
DROP POLICY "pemilik urus zon" ON zon_penghantaran;
CREATE POLICY "pemilik tambah zon" ON zon_penghantaran FOR INSERT WITH CHECK ((select is_pemilik()));
CREATE POLICY "pemilik kemaskini zon" ON zon_penghantaran FOR UPDATE USING ((select is_pemilik()));
CREATE POLICY "pemilik padam zon" ON zon_penghantaran FOR DELETE USING ((select is_pemilik()));
