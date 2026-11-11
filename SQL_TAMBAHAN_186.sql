-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 186 (DRAF, belum apply): Kad Telegram Lulus/Tolak utk permohonan padam
-- jenis 'pelupusan_stok' (resit pelupusan/tukar expired tersalah rekod).
--
-- Kes pencetus (11 Nov 2026): Nadia rekod R-261111-984 (lupus 1 beg Tamar Arabica, RM22)
-- tersalah, lalu buat semula sbg tukar R-261111-122. Bawaan Arabica dia 1 beg (sepatutnya 2).
-- Sebelum ini kad Telegram hanya sokong padam 'transaksi' & 'kedai'; pelupusan perlu buka web.
--
-- Pemilik LULUS dulu di Telegram (pengesahan 2 langkah sedia ada): tiada apa berubah sebelum
-- butang "Ya, Padam Kekal" ditekan. Salinan baris disimpan dlm private.arkib_padam.
-- Perlu deploy serentak: notifikasi-kelulusan-pemilik (butang untuk jenis ini).
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.telegram_putuskan_padam(p_admin_chat_id bigint, p_id text, p_tindakan text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
DECLARE
  v_admin_user_id uuid;
  v_p RECORD;
  v_trx RECORD;
  v_kedai RECORD;
  item jsonb;
  v_pekerja_id uuid;
  v_nama text;
  v_qty int;
  v_pulang int;
  v_pulih int;
  v_baki_stok text := '';
  v_lp RECORD;
  v_bil_lp int := 0;
  v_pulih_lp text := '';
BEGIN
  SELECT user_id INTO v_admin_user_id FROM telegram_admin WHERE chat_id = p_admin_chat_id AND aktif = true;
  IF v_admin_user_id IS NULL THEN
    RAISE EXCEPTION 'Chat Telegram ini tidak didaftarkan sebagai pemilik atau tidak aktif';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = v_admin_user_id AND role = 'pemilik') THEN
    RAISE EXCEPTION 'Akaun berkaitan bukan pemilik';
  END IF;
  IF p_tindakan NOT IN ('luluskan','tolak') THEN
    RAISE EXCEPTION 'Tindakan tidak sah: %', p_tindakan;
  END IF;

  SELECT * INTO v_p FROM permohonan_padam WHERE id = p_id AND status = 'menunggu' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Permohonan tidak dijumpai atau sudah diputuskan'; END IF;

  IF p_tindakan = 'tolak' THEN
    UPDATE permohonan_padam SET status = 'ditolak', diputuskan_oleh = v_admin_user_id, diputuskan_pada = now() WHERE id = p_id;
    RETURN 'Permohonan padam ' || COALESCE(v_p.rekod_label, v_p.rekod_id) || ' DITOLAK ✕ (rekod TIDAK dipadam)';
  END IF;

  IF v_p.jenis = 'kedai' THEN
    -- SQL 165: padam kedai. Hutang belum langsai = tolak (jangan hilangkan hutang senyap-senyap).
    SELECT * INTO v_kedai FROM kedai WHERE id = v_p.rekod_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Kedai sudah tiada (mungkin sudah dipadam)'; END IF;
    IF COALESCE(v_kedai.hutang, 0) > 0 THEN
      RAISE EXCEPTION 'Kedai ini masih berhutang RM% — selesaikan hutang dahulu sebelum padam', round(v_kedai.hutang::numeric, 2);
    END IF;
    INSERT INTO private.arkib_padam (jadual, rekod_id, permohonan_id, diputuskan_oleh, data)
    VALUES ('kedai', v_kedai.id, p_id, v_admin_user_id, to_jsonb(v_kedai));
    DELETE FROM kedai WHERE id = v_kedai.id;
    UPDATE permohonan_padam SET status = 'diluluskan', diputuskan_oleh = v_admin_user_id, diputuskan_pada = now() WHERE id = p_id;
    RETURN 'Kedai ' || v_kedai.nama || ' DIPADAM kekal ✅ (salinan disimpan dlm arkib)';
  END IF;

  IF v_p.jenis = 'pelupusan_stok' THEN
    -- SQL 186: padam resit pelupusan/tukar expired (rekod_id = NO. RESIT). Logik SAMA spt
    -- padam_resit_pelupusan() (SQL 138) tetapi tanpa is_pemilik() (service_role, tiada auth.uid()):
    -- pulihkan stok bawaan pekerja utk semua baris KECUALI jenis 'tukar_ambil' (asalnya dari kedai).
    FOR v_lp IN SELECT * FROM pelupusan_stok WHERE resit = v_p.rekod_id FOR UPDATE LOOP
      v_bil_lp := v_bil_lp + 1;
      INSERT INTO private.arkib_padam (jadual, rekod_id, permohonan_id, diputuskan_oleh, data)
      VALUES ('pelupusan_stok', v_lp.id, p_id, v_admin_user_id, to_jsonb(v_lp));
      IF v_lp.jenis IS DISTINCT FROM 'tukar_ambil' AND v_lp.pekerja_id IS NOT NULL THEN
        INSERT INTO stok_pekerja (pekerja_id, stok_id, kuantiti) VALUES (v_lp.pekerja_id, v_lp.stok_id, v_lp.kuantiti)
          ON CONFLICT (pekerja_id, stok_id) DO UPDATE SET kuantiti = stok_pekerja.kuantiti + v_lp.kuantiti;
        v_pulih_lp := v_pulih_lp || CASE WHEN v_pulih_lp = '' THEN '' ELSE ', ' END || v_lp.stok_id || ' +' || v_lp.kuantiti;
      END IF;
    END LOOP;
    IF v_bil_lp = 0 THEN RAISE EXCEPTION 'Resit pelupusan sudah tiada (mungkin sudah dipadam)'; END IF;
    DELETE FROM pelupusan_stok WHERE resit = v_p.rekod_id;
    UPDATE permohonan_padam SET status = 'diluluskan', diputuskan_oleh = v_admin_user_id, diputuskan_pada = now() WHERE id = p_id;
    RETURN 'Resit pelupusan ' || v_p.rekod_id || ' DIPADAM ✅'
      || CASE WHEN v_pulih_lp <> '' THEN ' — stok dipulangkan ke bawaan pekerja (' || v_pulih_lp || ')' ELSE '' END;
  END IF;

  IF v_p.jenis <> 'transaksi' THEN
    RAISE EXCEPTION 'Jenis "%" hanya boleh diluluskan di Sistem Pengurusan', v_p.jenis;
  END IF;

  SELECT * INTO v_trx FROM transaksi WHERE id = v_p.rekod_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Transaksi sudah tiada (mungkin sudah dipadam)'; END IF;

  BEGIN
    v_pekerja_id := v_trx.created_by::uuid;
  EXCEPTION WHEN others THEN
    v_pekerja_id := NULL;
  END;

  IF v_pekerja_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM baucar_bayaran
     WHERE pekerja_id = v_pekerja_id AND kategori = 'upah_harian'
       AND tarikh = (v_trx.tarikh_masa AT TIME ZONE 'Asia/Kuala_Lumpur')::date
       AND status IN ('diluluskan','dibayar')
  ) THEN
    RAISE EXCEPTION 'Baucar upah hari transaksi ini sudah diluluskan/dibayar — sila luluskan di Sistem Pengurusan (kos minyak perlu dikira)';
  END IF;

  INSERT INTO private.arkib_padam (jadual, rekod_id, permohonan_id, diputuskan_oleh, data)
  VALUES ('transaksi', v_trx.id, p_id, v_admin_user_id, to_jsonb(v_trx));

  FOR item IN SELECT * FROM jsonb_array_elements(v_trx.items) LOOP
    v_qty := COALESCE((item->>'qty')::int, 0);
    v_pulang := 0;
    IF v_trx.items_pulang IS NOT NULL THEN
      SELECT COALESCE(SUM((ip->>'qty')::int), 0) INTO v_pulang
        FROM jsonb_array_elements(v_trx.items_pulang) ip WHERE ip->>'stokId' = item->>'stokId';
    END IF;
    v_pulih := GREATEST(0, v_qty - v_pulang);
    IF v_pulih = 0 THEN CONTINUE; END IF;

    IF v_pekerja_id IS NOT NULL THEN
      INSERT INTO stok_pekerja (pekerja_id, stok_id, kuantiti) VALUES (v_pekerja_id, item->>'stokId', v_pulih)
        ON CONFLICT (pekerja_id, stok_id) DO UPDATE SET kuantiti = stok_pekerja.kuantiti + v_pulih;
      SELECT nama INTO v_nama FROM stok WHERE id = item->>'stokId';
      INSERT INTO serahan_produk (id, pekerja_id, stok_id, stok_nama, kuantiti, jenis, status)
        VALUES (gen_random_uuid()::text, v_pekerja_id, item->>'stokId', COALESCE(v_nama, item->>'stokId'), v_pulih, 'padam_pulang', 'disahkan');
    ELSE
      UPDATE stok SET stok = stok + v_pulih WHERE id = item->>'stokId';
    END IF;
    v_baki_stok := v_baki_stok || CASE WHEN v_baki_stok = '' THEN '' ELSE ', ' END || (item->>'stokId') || ' +' || v_pulih;
  END LOOP;

  IF v_trx.status = 'hutang' AND v_trx.kedai_id IS NOT NULL THEN
    UPDATE kedai SET hutang = GREATEST(0, hutang - v_trx.jumlah) WHERE id = v_trx.kedai_id;
  END IF;

  DELETE FROM transaksi WHERE id = v_trx.id;
  UPDATE permohonan_padam SET status = 'diluluskan', diputuskan_oleh = v_admin_user_id, diputuskan_pada = now() WHERE id = p_id;

  RETURN 'Transaksi ' || COALESCE(v_trx.resit, v_trx.id) || ' DIPADAM kekal ✅'
    || CASE WHEN v_baki_stok <> '' THEN ' — stok dipulangkan ke bawaan pekerja (' || v_baki_stok || ')' ELSE '' END
    || CASE WHEN v_trx.status = 'hutang' THEN ' — hutang kedai ditolak' ELSE '' END;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.telegram_putuskan_padam(bigint, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.telegram_putuskan_padam(bigint, text, text) TO service_role;

-- ── Permohonan utk kes R-261111-984 (jalankan SELEPAS pemilik setuju; kad Telegram akan sampai) ──
-- Tiada apa dipadam di sini; ia hanya mencipta permohonan menunggu. Padam berlaku bila pemilik
-- tekan Luluskan -> Ya, Padam Kekal di Telegram. Dijangka stok S005 Nadia 1 -> 2.
-- Semak dahulu (mesti 1 baris, jenis 'lupus'):
--   SELECT id, jenis, stok_id, kuantiti FROM pelupusan_stok WHERE resit = 'R-261111-984';
INSERT INTO permohonan_padam (id, jenis, rekod_id, rekod_label, sebab, pekerja_id)
VALUES ('PP' || substr(md5(random()::text), 1, 10), 'pelupusan_stok', 'R-261111-984',
        'Resit R-261111-984 · Pelupusan 1 beg Tamar Arabica (RM22.00)',
        'Tersalah rekod pelupusan; sudah direkod semula sbg tukar R-261111-122',
        '35ded3aa-005a-438b-8da4-8d224913338c');
