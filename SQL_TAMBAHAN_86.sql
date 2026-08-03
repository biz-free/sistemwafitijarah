-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 86: padam_transaksi_kedai() kini auto-batal baucar
-- harian USANG (draf/diluluskan) — sama pattern spt submit_penghantaran
-- (SQL_TAMBAHAN_82) yang dah batal baucar bila transaksi BAHARU
-- ditambah. Kes ni bahagian yang tertinggal: bila transaksi DIPADAM,
-- baucar sedia ada utk pekerja+tarikh tu turut jadi usang (jumlah upah/
-- cash ditangan yang dibekukan dlm baucar tu dah tak padan realiti).
--
-- Punca sebenar isu Nadia 28 Julai (siasatan): baucar PV-2026-0014
-- dijana dgn Cash Ditangan RM205, tapi satu transaksi tunai RM24 hari
-- yang sama dipadam SELEPAS baucar dijana — baucar tu tak pernah
-- dibatalkan/dijana semula, jadi paparan "Pekerja perlu serah lebihan"
-- dia kekal guna angka lama (RM131.78) walaupun angka sebenar (guna
-- data transaksi TERKINI) patutnya RM107.78. Kad "Cash Dipegang Semua
-- Pekerja" (kiraCashDipegang()) TAK terjejas isu ni sebab ia sentiasa
-- kira terus dari data transaksi LIVE, bukan baucar yang dibekukan.
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.padam_transaksi_kedai(p_id text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE v_trx RECORD; item jsonb; v_pekerja_id uuid; v_nama text; v_qty int;
BEGIN
  IF NOT is_pemilik() THEN RAISE EXCEPTION 'Hanya pemilik boleh padam transaksi'; END IF;

  SELECT * INTO v_trx FROM transaksi WHERE id = p_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Transaksi tidak dijumpai'; END IF;

  BEGIN
    v_pekerja_id := v_trx.created_by::uuid;
  EXCEPTION WHEN others THEN
    v_pekerja_id := NULL;
  END;

  FOR item IN SELECT * FROM jsonb_array_elements(v_trx.items) LOOP
    v_qty := (item->>'qty')::int;
    IF v_pekerja_id IS NOT NULL THEN
      INSERT INTO stok_pekerja (pekerja_id, stok_id, kuantiti) VALUES (v_pekerja_id, item->>'stokId', v_qty)
        ON CONFLICT (pekerja_id, stok_id) DO UPDATE SET kuantiti = stok_pekerja.kuantiti + v_qty;
      SELECT nama INTO v_nama FROM stok WHERE id = item->>'stokId';
      INSERT INTO serahan_produk (id, pekerja_id, stok_id, stok_nama, kuantiti, jenis, status)
        VALUES (gen_random_uuid()::text, v_pekerja_id, item->>'stokId', COALESCE(v_nama, item->>'stokId'), v_qty, 'padam_pulang', 'disahkan');
    ELSE
      UPDATE stok SET stok = stok + v_qty WHERE id = item->>'stokId';
    END IF;
  END LOOP;

  IF v_trx.status = 'hutang' AND v_trx.kedai_id IS NOT NULL THEN
    UPDATE kedai SET hutang = GREATEST(0, hutang - v_trx.jumlah) WHERE id = v_trx.kedai_id;
  END IF;

  IF v_pekerja_id IS NOT NULL THEN
    UPDATE baucar_bayaran SET status = 'dibatalkan'
      WHERE pekerja_id = v_pekerja_id AND kategori = 'upah_harian'
        AND tarikh = (v_trx.tarikh_masa AT TIME ZONE 'Asia/Kuala_Lumpur')::date
        AND status IN ('draf','diluluskan');
  END IF;

  DELETE FROM transaksi WHERE id = p_id;
END;
$function$;
