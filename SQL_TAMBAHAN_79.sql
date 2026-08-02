-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 79: Padam Transaksi Kedai — pulangkan stok ke STOK
-- BAWAAN PEKERJA yang hantar asalnya (bukan terus ke gudang pusat).
--
-- PUNCA lama: padam_transaksi_kedai() buat "UPDATE stok SET stok =
-- stok + qty" (terus ke gudang) — barang konsepnya tak pernah betul-
-- betul "keluar" drpd bag pekerja bila satu jualan/rekod dibatalkan
-- (ia masih di tangan/kawasan pekerja tu), jadi patut pulang ke
-- stok_pekerja pekerja berkenaan, bukan gudang terus.
--
-- Fallback ke gudang KEKAL utk kes created_by tiada/tak sah (rekod
-- lama/data tak lengkap) — elak stok "hilang" kalau pekerja tak
-- dapat dikenal pasti.
--
-- Turut rekod ke serahan_produk (jenis baharu 'padam_pulang',
-- status terus 'disahkan' sebab ia tindakan pemilik yang dah
-- selesai, bukan permohonan menunggu) — supaya pergerakan ni boleh
-- dijejak/audit sama macam ambil/pulang stok biasa (nampak di
-- Sejarah Serahan Saya pekerja & Sejarah Pergerakan Stok pemilik).
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

  DELETE FROM transaksi WHERE id = p_id;
END;
$function$;
