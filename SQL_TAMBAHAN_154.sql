-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 154: Kad Telegram "Luluskan & Padam / Tolak" utk PERMOHONAN PADAM
-- jenis 'transaksi' (sebelum ini baca sahaja di Telegram — /padam).
--
-- Peraturan keselamatan:
--   • Hanya jenis 'transaksi'. Jenis lain (serahan_produk, kedai, pre_order,
--     serahan_cash, pelupusan_stok) TETAP diputuskan di Sistem Pengurusan.
--   • Telegram: Luluskan = pengesahan DUA LANGKAH ("Ya, Padam Kekal") sebelum DB dipanggil.
--   • Jika baucar upah harian pekerja pada tarikh transaksi sudah diluluskan/dibayar,
--     fungsi MENOLAK (kos minyak perlu dikira di Sistem Pengurusan) — tiada pelarasan senyap.
--   • Salinan PENUH baris transaksi disimpan ke private.arkib_padam SEBELUM dipadam
--     (boleh dipulihkan jika tersilap).
--   • Stok dipulangkan ke bawaan pekerja: qty - qty yg SUDAH dipulangkan (items_pulang)
--     supaya konsainmen berpulangan tidak dikira dua kali (butang web sedia ada
--     padam_transaksi_kedai() TIDAK berbuat begini — TIDAK diubah di sini).
--   • Hutang kedai ditolak jika status transaksi 'hutang'.
--   • Pemakluman ke WhatsApp: dicetuskan automatik oleh SQL 153 (permohonan_padam menunggu -> diluluskan/ditolak).
-- ═══════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS private.arkib_padam (
  id bigserial PRIMARY KEY,
  dicipta timestamptz NOT NULL DEFAULT now(),
  jadual text NOT NULL,
  rekod_id text NOT NULL,
  permohonan_id text,
  diputuskan_oleh uuid,
  data jsonb NOT NULL
);
ALTER TABLE private.arkib_padam ENABLE ROW LEVEL SECURITY;  -- tiada polisi = tiada akses terus

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
  item jsonb;
  v_pekerja_id uuid;
  v_nama text;
  v_qty int;
  v_pulang int;
  v_pulih int;
  v_baki_stok text := '';
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
