-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 152: Kad transfer (SQL 151) — "✕ Belum Masuk" kini AUTO tukar
-- transaksi Online Transfer itu kepada HUTANG.
--
-- Bila pemilik tekan "✕ Belum Masuk" (duit belum masuk bank):
--   • transaksi.kaedah_bayaran -> 'hutang', status -> 'hutang'
--   • kedai.hutang += jumlah (jika ada kedai) — sama seperti
--     tukar_kaedah_bayaran_transaksi() (SQL 90/91)
--   • tarikh_akhir_bayaran = hari keputusan + 7 hari (waktu Malaysia), supaya
--     peringatan lewat bayar berjalan. Pemilik boleh ubah kemudian melalui
--     Sistem Pengurusan (edit_tarikh_akhir_bayaran_transaksi).
--   • baucar upah harian pekerja pada tarikh transaksi yg masih draf/diluluskan
--     dibatalkan (peraturan SEDIA ADA bila kaedah bayaran ditukar); baucar
--     yg sudah dibayar tidak disentuh.
-- "✅ Duit Masuk" tidak mengubah apa-apa (kekal transfer/selesai).
-- Diputuskan SEKALI sahaja (pemakluman_kelulusan) dan baris dikunci (FOR UPDATE).
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.telegram_putuskan_transfer(p_admin_chat_id bigint, p_id text, p_status text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
DECLARE
  v_admin_user_id uuid;
  v_tx RECORD;
  v_pekerja_id uuid;
  v_kedai_nama text;
  v_info text := '';
  v_tarikh_hari date := (now() AT TIME ZONE 'Asia/Kuala_Lumpur')::date;
BEGIN
  SELECT user_id INTO v_admin_user_id FROM telegram_admin WHERE chat_id = p_admin_chat_id AND aktif = true;
  IF v_admin_user_id IS NULL THEN
    RAISE EXCEPTION 'Chat Telegram ini tidak didaftarkan sebagai pemilik atau tidak aktif';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = v_admin_user_id AND role = 'pemilik') THEN
    RAISE EXCEPTION 'Akaun berkaitan bukan pemilik';
  END IF;
  IF p_status NOT IN ('disahkan','ditolak') THEN
    RAISE EXCEPTION 'Status tidak sah: %', p_status;
  END IF;

  SELECT id, jumlah, resit, kaedah_bayaran, status, kedai_id, created_by, tarikh_masa
    INTO v_tx FROM transaksi WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Transaksi tidak dijumpai (mungkin sudah dipadam)'; END IF;
  IF v_tx.kaedah_bayaran <> 'transfer' THEN RAISE EXCEPTION 'Transaksi ini bukan Online Transfer (mungkin sudah ditukar kaedah bayaran)'; END IF;
  IF EXISTS (SELECT 1 FROM private.pemakluman_kelulusan WHERE jadual = 'transaksi' AND rekod_id = p_id) THEN
    RAISE EXCEPTION 'Transfer ini sudah diputuskan sebelum ini';
  END IF;

  IF p_status = 'disahkan' THEN
    RETURN 'Online Transfer RM' || to_char(v_tx.jumlah, 'FM999999990.00') || ' #' || COALESCE(v_tx.resit, v_tx.id)
      || ' — DUIT SUDAH MASUK bank ✅';
  END IF;

  -- Belum masuk: tukar kepada HUTANG
  IF v_tx.status IS DISTINCT FROM 'hutang' THEN
    IF v_tx.kedai_id IS NOT NULL THEN
      UPDATE kedai SET hutang = hutang + v_tx.jumlah WHERE id = v_tx.kedai_id;
      SELECT nama INTO v_kedai_nama FROM kedai WHERE id = v_tx.kedai_id;
    END IF;
    UPDATE transaksi
       SET kaedah_bayaran = 'hutang', status = 'hutang', tarikh_akhir_bayaran = v_tarikh_hari + 7
     WHERE id = p_id;

    BEGIN
      v_pekerja_id := v_tx.created_by::uuid;
    EXCEPTION WHEN others THEN
      v_pekerja_id := NULL;
    END;
    IF v_pekerja_id IS NOT NULL THEN
      UPDATE baucar_bayaran SET status = 'dibatalkan'
       WHERE pekerja_id = v_pekerja_id AND kategori = 'upah_harian'
         AND tarikh = (v_tx.tarikh_masa AT TIME ZONE 'Asia/Kuala_Lumpur')::date
         AND status IN ('draf','diluluskan');
    END IF;

    v_info := ' — DITUKAR KEPADA HUTANG' || COALESCE(' (' || v_kedai_nama || ')', '')
      || ', akhir bayar ' || to_char(v_tarikh_hari + 7, 'DD/MM/YYYY');
  END IF;

  RETURN 'Online Transfer RM' || to_char(v_tx.jumlah, 'FM999999990.00') || ' #' || COALESCE(v_tx.resit, v_tx.id)
    || ' — DUIT BELUM MASUK bank ✕' || v_info;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.telegram_putuskan_transfer(bigint, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.telegram_putuskan_transfer(bigint, text, text) TO service_role;
