-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 66: Semakan keselamatan menyeluruh — SEMUA fungsi
-- custom di schema public yang guna auth.uid() tanpa corak
-- semakan biasa, susulan penemuan cipta_baucar_harian &
-- ambil_stok_pekerja (SQL_TAMBAHAN_64).
--
-- Latar: Supabase projek ini bagi EXECUTE kepada peranan "anon"
-- (tanpa log masuk) pada SEMUA fungsi custom baru di public
-- secara LALAI. Ini bermakna mana-mana RPC "dalaman" (staff
-- sahaja) boleh dipanggil oleh SESIAPA di internet tanpa log
-- masuk, MELAINKAN badan fungsi itu sendiri tolak pemanggil
-- tanpa log masuk.
--
-- 10 fungsi (submit_penghantaran dikira 4 overload = 13 definisi)
-- yang guna auth.uid() tanpa corak semakan "auth.uid() IS NULL"
-- atau "is_pemilik()" yang jelas, disemak SATU PERSATU (baca
-- pg_get_functiondef penuh, bukan hanya heuristik carian teks):
--
-- SELAMAT (ada semakan eksplisit "EXISTS profiles WHERE id =
-- auth.uid()" atau "role = 'pemilik'" — bila auth.uid() = NULL
-- utk anon, "= NULL" menilai NULL bukan TRUE, EXISTS gagal,
-- exception dilontar seperti sepatutnya):
--   claim_preorder, hantar_permohonan_cuti, submit_penghantaran
--   (semua 4 overload), rekod_bayaran, tugaskan_preorder.
--
-- SELAMAT SECARA KEBETULAN (tiada semakan log masuk eksplisit,
-- TETAPI satu-satunya mutasi data ditapis "WHERE ... = auth.uid()"
-- — apabila auth.uid() = NULL, syarat itu TIDAK PERNAH padan
-- mana-mana baris, walaupun baris itu sendiri ada pekerja_id
-- NULL, kerana "NULL = NULL" turut menilai NULL dalam SQL — jadi
-- anon sentiasa gagal di semakan "IF NOT FOUND" SEBELUM sebarang
-- tulisan berlaku):
--   kemaskini_profil_sendiri (WHERE id = auth.uid() — no-op utk
--   anon sebab profiles.id tak boleh NULL), lupus_stok_pekerja,
--   pulang_stok_pekerja, serah_produk_reject (ketiga-tiga guna
--   WHERE pekerja_id = auth.uid() sebelum sebarang INSERT/UPDATE
--   lain berlaku).
-- Kesemua ini disahkan LANGSUNG guna panggilan RPC anon sebenar
-- (anon key awam) — anon sama ada ditolak dengan exception, atau
-- (kemaskini_profil_sendiri) berjaya tanpa ubah sebarang baris.
--
-- ⚠️ TERDEDAH SEBENAR — tukar_stok_expired_kedai: LANGSUNG tiada
-- semakan auth.uid(), dan KEDUA-DUA mutasi datanya — INSERT
-- pelupusan_stok (rekod pelupusan/kerugian stok) bagi p_items_expired,
-- dan UPDATE kedai.last_visit di penghujung fungsi — TIDAK ditapis
-- ikut auth.uid() langsung. Disahkan boleh dieksploitasi melalui
-- panggilan RPC anon SEBENAR sebelum pembetulan: panggilan berjaya
-- (HTTP 204, tiada ralat) walaupun tanpa sebarang token log masuk,
-- membenarkan SESIAPA di internet cipta rekod pelupusan stok palsu
-- (label kos kerugian) bagi mana-mana kedai & produk, dan ubah
-- kedai.last_visit mana-mana kedai. Dibetulkan dengan corak sama
-- seperti SQL_TAMBAHAN_64: "IF auth.uid() IS NULL THEN RAISE
-- EXCEPTION" eksplisit di awal fungsi (bukan sekatan role — mana-
-- mana staff log masuk kekal dibenarkan guna fungsi ini, sama
-- seperti submit_penghantaran). Disahkan pembetulan berkesan
-- melalui panggilan RPC anon SEBENAR selepas — ditolak dengan
-- "Log masuk diperlukan".
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.tukar_stok_expired_kedai(p_kedai_id text, p_items_expired jsonb, p_items_gantian jsonb, p_sebab_expired text DEFAULT 'expired'::text, p_nota text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE item jsonb; v_harga_beli float; v_qty int;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Log masuk diperlukan';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM kedai WHERE id = p_kedai_id) THEN
    RAISE EXCEPTION 'Kedai tidak dijumpai';
  END IF;

  FOR item IN SELECT * FROM jsonb_array_elements(COALESCE(p_items_expired, '[]'::jsonb)) LOOP
    v_qty := (item->>'qty')::int;
    IF v_qty <= 0 THEN RAISE EXCEPTION 'Kuantiti mesti lebih 0'; END IF;
    SELECT harga_beli INTO v_harga_beli FROM stok WHERE id = item->>'stokId';
    IF v_harga_beli IS NULL THEN RAISE EXCEPTION 'Produk % tidak wujud atau telah dipadam', item->>'stokId'; END IF;
    INSERT INTO pelupusan_stok (id, pekerja_id, kedai_id, stok_id, kuantiti, sebab, jenis, nota, kos)
      VALUES (gen_random_uuid()::text, auth.uid(), p_kedai_id, item->>'stokId', v_qty, p_sebab_expired, 'tukar_ambil', p_nota, v_harga_beli * v_qty);
  END LOOP;

  FOR item IN SELECT * FROM jsonb_array_elements(COALESCE(p_items_gantian, '[]'::jsonb)) LOOP
    v_qty := (item->>'qty')::int;
    IF v_qty <= 0 THEN RAISE EXCEPTION 'Kuantiti mesti lebih 0'; END IF;
    UPDATE stok_pekerja SET kuantiti = kuantiti - v_qty
      WHERE pekerja_id = auth.uid() AND stok_id = item->>'stokId' AND kuantiti >= v_qty;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Stok bawaan anda tidak mencukupi untuk %', item->>'stokId';
    END IF;
    SELECT harga_beli INTO v_harga_beli FROM stok WHERE id = item->>'stokId';
    INSERT INTO pelupusan_stok (id, pekerja_id, kedai_id, stok_id, kuantiti, sebab, jenis, nota, kos)
      VALUES (gen_random_uuid()::text, auth.uid(), p_kedai_id, item->>'stokId', v_qty, 'gantian_tukar', 'tukar_beri', p_nota, COALESCE(v_harga_beli, 0) * v_qty);
  END LOOP;

  UPDATE kedai SET last_visit = CURRENT_DATE::text WHERE id = p_kedai_id;
END;
$function$;

-- ── Default privileges: sengaja diselidik, bukan diandaikan ──
-- REVOKE ... FROM PUBLIC biasa (dicuba sesi lepas) TIDAK cukup sebab
-- grant terus kepada anon (bukan diwarisi dari PUBLIC). Disiasat
-- puncanya: pg_default_acl utk (role=postgres, schema=public,
-- objtype='f') ADA baris eksplisit anon=X — ini yang bagi EXECUTE
-- kepada anon pada SEMUA fungsi baru. Dibetulkan di bawah (buang
-- anon drpd default itu, jadikan akses 8 RPC awam sedia ada —
-- dipakai index.html/pesan.html/produk-preview — eksplisit, tiada
-- perubahan tingkah laku sebab ia dah ada akses via default lama).
--
-- ⚠️ PENTING — DIUJI & DISAHKAN: langkah di atas SAHAJA tidak cukup
-- menutup jurang sepenuhnya utk fungsi BAHARU akan datang. PostgreSQL
-- turut bagi EXECUTE kepada PUBLIC secara lalai (hardcoded) pada
-- SETIAP fungsi baharu, berasingan drpd default ACL peranan bernama
-- — dan "anon" automatik mewarisi via PUBLIC itu. Cubaan tutup guna
-- "ALTER DEFAULT PRIVILEGES ... IN SCHEMA public REVOKE ... FROM
-- PUBLIC" turut TIDAK berkesan (disahkan guna fungsi ujian sekali
-- pakai selepas jalankan arahan itu — anon masih boleh EXECUTE).
-- Ini ISU SEDIA MAKLUM Supabase, bukan silap konfigurasi projek ini
-- (rujuk: github.com/supabase/supabase issue #43884 — "Unexpected
-- Default EXECUTE Privileges on Functions in API Schema"; satu-
-- satunya penyelesaian yang benar2 berkesan ialah REVOKE manual
-- selepas setiap CREATE FUNCTION, atau event trigger automatik).
--
-- KEPUTUSAN: semakan auth.uid() DALAM setiap fungsi kekal PERTAHANAN
-- UTAMA & WAJIB (bukan pilihan) — bukan grant/privilege. Perubahan
-- default di bawah adalah lapisan tambahan (defence-in-depth) sahaja,
-- bukan pengganti semakan dalaman.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.senarai_produk_awam() TO anon;
GRANT EXECUTE ON FUNCTION public.jejak_pesanan_awam(text) TO anon;
GRANT EXECUTE ON FUNCTION public.semak_ganjaran_rujukan_saya(text) TO anon;
GRANT EXECUTE ON FUNCTION public.validasi_baucar(text, text, double precision) TO anon;
GRANT EXECUTE ON FUNCTION public.validasi_rujukan(text, text) TO anon;
GRANT EXECUTE ON FUNCTION public.semak_status_pesanan(text) TO anon;
GRANT EXECUTE ON FUNCTION public.maklumat_kedai_awam(text) TO anon;
GRANT EXECUTE ON FUNCTION public.cari_kedai_ikut_telefon(text) TO anon;
