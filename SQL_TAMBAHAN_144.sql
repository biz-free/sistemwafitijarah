-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 144: Pemilik boleh EDIT Tarikh Akhir Bayaran Hutang terus
-- di Tempahan > Transaksi Kedai — tanpa perlu padam & minta pekerja hantar
-- semula. Kes guna: kedai minta lanjutan tempoh bayar, atau pekerja tersilap
-- masukkan tarikh semasa hantar (medan "Tarikh Akhir Bayaran (Wajib)" di
-- borang Hantar > Catat Hutang).
--
-- Skop: hanya transaksi berstatus 'hutang' (padan dgn cara medan ni
-- digunakan di seluruh sistem — lihat renderSejarah()/resit notaDue).
-- Tiada kesan pada jumlah/hutang kedai — cuma tarikh peringatan.
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.edit_tarikh_akhir_bayaran_transaksi(p_id text, p_tarikh_akhir_baru date)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_trx RECORD;
BEGIN
  IF NOT is_pemilik() THEN
    RAISE EXCEPTION 'Hanya pemilik boleh edit tarikh akhir bayaran';
  END IF;
  IF p_tarikh_akhir_baru IS NULL THEN
    RAISE EXCEPTION 'Tarikh mesti diisi';
  END IF;

  SELECT * INTO v_trx FROM transaksi WHERE id = p_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Transaksi tidak dijumpai'; END IF;
  IF v_trx.status <> 'hutang' THEN
    RAISE EXCEPTION 'Tarikh akhir bayaran hanya relevan untuk transaksi berstatus hutang (status semasa: %)', v_trx.status;
  END IF;

  UPDATE transaksi SET tarikh_akhir_bayaran = p_tarikh_akhir_baru WHERE id = p_id;
END;
$function$;
