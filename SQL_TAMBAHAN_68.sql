-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 68: Tutup kebocoran data pre_order — sesiapa
-- boleh baca SEMUA pre-order belum ditugaskan tanpa log masuk.
--
-- Susulan arahan semak advisories RLS ("rls_policy_always_true")
-- selepas SQL_TAMBAHAN_66/67 (jurang EXECUTE fungsi). 4 jadual
-- disemak: kunjungan_web, pemohon_program, pesanan_edagang,
-- pre_order.
--
-- kunjungan_web — SELAMAT: hanya jadual analitik kunjungan (page/
-- UTM/referrer/session, tiada PII), tiada polisi SELECT langsung
-- utk sesiapa (hanya pemilik) — INSERT awam ("WITH CHECK true")
-- memang sepatutnya begitu (beacon tracking).
--
-- pesanan_edagang & pre_order (INSERT) — SELAMAT walaupun "WITH
-- CHECK true": kedua-duanya ada trigger BEFORE INSERT
-- (validasi_harga_pesanan_edagang / validasi_harga_pre_order) yang
-- kira semula harga terus dari jadual stok & paksa status='baru' —
-- klien tak boleh palsukan harga atau status pra-lulus.
--
-- ⚠️ pre_order (SELECT) — TERDEDAH SEBENAR: polisi "staff boleh
-- baca pre-order" ada syarat "(assigned_pekerja_id IS NULL)" yang
-- LANGSUNG tiada rujukan auth.uid() — jadi terpakai kepada SEMUA
-- peranan termasuk anon. Disahkan SECARA LANGSUNG hujung-ke-hujung
-- tanpa sebarang log masuk: INSERT baris ujian via anon key awam,
-- kemudian SELECT balik baris SAMA — kedai_telefon, alamat, lat/
-- lng, status_bayaran semua berjaya dibaca. Oleh sebab pre_order
-- yang belum ditugaskan adalah KEADAAN NORMAL (antara pelanggan
-- hantar & staff "claim"), ini jurang kebocoran PII/bayaran yang
-- sentiasa aktif, bukan kes tepi. Dibetulkan dengan tambah syarat
-- "EXISTS profiles WHERE id = auth.uid()" (corak sama seperti
-- polisi "staff boleh baca" di kategori_stok/pemohon_program/
-- route_kedai) sebelum cabang "belum ditugaskan/ditugaskan kpd
-- saya" terpakai. Disahkan selepas pembetulan: (1) anon baca baris
-- SAMA → [] kosong; (2) simulasi sesi pekerja (bukan pemilik) guna
-- SET LOCAL ROLE authenticated + request.jwt.claims → tetap nampak
-- pre-order belum ditugaskan (papan pengurusan.html "Pre-Order
-- Baru" tidak terjejas). Baris ujian dipadam selepas verifikasi.
--
-- pemohon_program — NOTA MINOR (TIDAK dibetulkan, keutamaan
-- rendah): "WITH CHECK true" pada INSERT tiada trigger memaksa
-- status awal (tiada pemalsuan harga/kebenaran sistem sebenar
-- berlaku — jadual ini cuma rekod permohonan; pengurusan.html
-- papar SEMUA permohonan tanpa tapis status, jadi status palsu
-- tak sembunyikan rekod drpd staff). Boleh diperbaiki lain kali
-- jika perlu (tambah trigger paksa status='baru' spt pre_order).
-- ═══════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "staff boleh baca pre-order" ON public.pre_order;
CREATE POLICY "staff boleh baca pre-order" ON public.pre_order
FOR SELECT
USING (
  is_pemilik()
  OR (
    EXISTS (SELECT 1 FROM profiles WHERE profiles.id = auth.uid())
    AND (assigned_pekerja_id IS NULL OR assigned_pekerja_id = auth.uid())
  )
);
