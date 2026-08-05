-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 88: Pemilik boleh betulkan kaedah bayaran transaksi kedai
-- yang tersilap key-in oleh pekerja (cth: pilih Tunai sepatutnya Consignment,
-- atau Hutang sepatutnya Transfer).
--
-- Bila kaedah bayaran ditukar, status (selesai/hutang) turut dilaraskan
-- (hutang/consignment => hutang, selain itu => selesai) ikut logik SAMA
-- dgn submit_penghantaran, dan kedai.hutang dilaraskan ikut PERBEZAAN
-- status lama vs baharu (elak salah kira/double-count). Baucar harian
-- sedia ada (draf/diluluskan) utk pekerja+tarikh transaksi ni turut
-- dibatalkan sebab kaedah bayaran mempengaruhi kelayakan upah pekerja
-- (consignment blm sahkan = upah 0) — sama pattern spt SQL_TAMBAHAN_82/86.
--
-- SENGAJA TIDAK sentuh jumlah/jumlah_asal/diskaun_peratus (harga/diskaun
-- yang dah dikunci masa jualan) — ini cuma pembetulan KAEDAH bayaran,
-- bukan re-harga jualan.
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.tukar_kaedah_bayaran_transaksi(p_id text, p_kaedah_bayaran_baru text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE v_trx RECORD; v_status_baru text; v_pekerja_id uuid;
BEGIN
  IF NOT is_pemilik() THEN RAISE EXCEPTION 'Hanya pemilik boleh tukar kaedah bayaran'; END IF;
  IF p_kaedah_bayaran_baru NOT IN ('tunai','transfer','hutang','consignment') THEN
    RAISE EXCEPTION 'Kaedah bayaran tidak sah: %', p_kaedah_bayaran_baru;
  END IF;

  SELECT * INTO v_trx FROM transaksi WHERE id = p_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Transaksi tidak dijumpai'; END IF;

  v_status_baru := CASE WHEN p_kaedah_bayaran_baru IN ('hutang','consignment') THEN 'hutang' ELSE 'selesai' END;

  IF v_trx.kedai_id IS NOT NULL AND v_trx.status IS DISTINCT FROM v_status_baru THEN
    IF v_status_baru = 'hutang' THEN
      UPDATE kedai SET hutang = hutang + v_trx.jumlah WHERE id = v_trx.kedai_id;
    ELSE
      UPDATE kedai SET hutang = GREATEST(0, hutang - v_trx.jumlah) WHERE id = v_trx.kedai_id;
    END IF;
  END IF;

  UPDATE transaksi SET kaedah_bayaran = p_kaedah_bayaran_baru, status = v_status_baru WHERE id = p_id;

  BEGIN
    v_pekerja_id := v_trx.created_by::uuid;
  EXCEPTION WHEN others THEN
    v_pekerja_id := NULL;
  END;

  IF v_pekerja_id IS NOT NULL THEN
    UPDATE baucar_bayaran SET status = 'dibatalkan'
      WHERE pekerja_id = v_pekerja_id AND kategori = 'upah_harian'
        AND tarikh = (v_trx.tarikh_masa AT TIME ZONE 'Asia/Kuala_Lumpur')::date
        AND status IN ('draf','diluluskan');
  END IF;
END;
$function$;
