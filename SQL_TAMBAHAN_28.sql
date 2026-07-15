-- ═══════════════════════════════════════════════════════════
--  WAFI TIJARAH TRADING — SQL TAMBAHAN #28
--  Jalankan SEKALI sahaja dalam Supabase SQL Editor.
--  (Consignment: upah pekerja untuk penghantaran consignment "letak
--   barang, bayar lepas jual" kini hanya dikira SELEPAS kedai sahkan
--   jualan sebenar — bukan serta-merta bila barang dihantar. Sokong
--   jualan separa: kuantiti tak terjual tak dikira dalam upah.)
-- ═══════════════════════════════════════════════════════════

ALTER TABLE transaksi ADD COLUMN IF NOT EXISTS items_terjual jsonb;
ALTER TABLE transaksi ADD COLUMN IF NOT EXISTS jualan_disahkan boolean NOT NULL DEFAULT true;
ALTER TABLE transaksi ADD COLUMN IF NOT EXISTS disahkan_oleh uuid REFERENCES auth.users(id);
ALTER TABLE transaksi ADD COLUMN IF NOT EXISTS disahkan_pada timestamptz;

-- Kemaskini submit_penghantaran: penghantaran consignment bermula sebagai BELUM disahkan jual
-- (semua kaedah bayaran lain kekal disahkan serta-merta seperti sebelum ini, tiada perubahan tingkah laku).
CREATE OR REPLACE FUNCTION submit_penghantaran(
  p_id text, p_kedai_id text, p_items jsonb, p_jumlah float,
  p_status text, p_nota text, p_resit text, p_jarak_km float DEFAULT 0,
  p_nama_pembeli text DEFAULT NULL,
  p_kaedah_bayaran text DEFAULT 'tunai', p_jumlah_asal float DEFAULT NULL, p_diskaun_peratus float DEFAULT 0
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE item jsonb;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid()) THEN
    RAISE EXCEPTION 'Tidak dibenarkan';
  END IF;

  FOR item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    UPDATE stok_pekerja SET kuantiti = kuantiti - (item->>'qty')::int
      WHERE pekerja_id = auth.uid() AND stok_id = item->>'stokId' AND kuantiti >= (item->>'qty')::int;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Stok bawaan anda tidak mencukupi untuk %', item->>'stokId';
    END IF;
  END LOOP;

  INSERT INTO transaksi (id, kedai_id, nama_pembeli, items, jumlah, status, nota, resit, jarak_km, created_by, kaedah_bayaran, jumlah_asal, diskaun_peratus, jualan_disahkan)
  VALUES (p_id, p_kedai_id, p_nama_pembeli, p_items, p_jumlah, p_status, p_nota, p_resit, p_jarak_km, auth.uid()::text, p_kaedah_bayaran, COALESCE(p_jumlah_asal, p_jumlah), p_diskaun_peratus, (p_kaedah_bayaran <> 'consignment'));

  UPDATE kedai SET
    hutang = hutang + (CASE WHEN p_status = 'hutang' THEN p_jumlah ELSE 0 END),
    last_visit = CURRENT_DATE::text
  WHERE id = p_kedai_id;
END;
$$;

-- Sahkan jualan consignment (pemilik ATAU pekerja yang buat penghantaran asal) — sokong jualan separa.
-- Upah hanya dikira untuk kuantiti yang disahkan terjual (lihat jumlahUpahTransaksi() di pengurusan.html).
CREATE OR REPLACE FUNCTION sahkan_jualan_konsainan(p_transaksi_id text, p_items_terjual jsonb) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_trx RECORD;
  item jsonb;
  v_qty_asal int;
  v_qty_jual int;
BEGIN
  SELECT * INTO v_trx FROM transaksi WHERE id = p_transaksi_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Transaksi tidak dijumpai'; END IF;
  IF NOT (is_pemilik() OR v_trx.created_by = auth.uid()::text) THEN
    RAISE EXCEPTION 'Tidak dibenarkan sahkan jualan transaksi ini';
  END IF;
  IF v_trx.kaedah_bayaran <> 'consignment' THEN RAISE EXCEPTION 'Transaksi ini bukan consignment'; END IF;
  IF v_trx.jualan_disahkan THEN RAISE EXCEPTION 'Jualan sudah disahkan sebelum ini'; END IF;

  FOR item IN SELECT * FROM jsonb_array_elements(p_items_terjual) LOOP
    v_qty_jual := (item->>'qty')::int;
    SELECT (i->>'qty')::int INTO v_qty_asal FROM jsonb_array_elements(v_trx.items) i WHERE i->>'stokId' = item->>'stokId';
    IF v_qty_asal IS NULL OR v_qty_jual IS NULL OR v_qty_jual < 0 OR v_qty_jual > v_qty_asal THEN
      RAISE EXCEPTION 'Kuantiti terjual tidak sah untuk produk %', item->>'stokId';
    END IF;
  END LOOP;

  UPDATE transaksi SET
    items_terjual = p_items_terjual,
    jualan_disahkan = true,
    disahkan_oleh = auth.uid(),
    disahkan_pada = now()
  WHERE id = p_transaksi_id;
END;
$$;
GRANT EXECUTE ON FUNCTION sahkan_jualan_konsainan(text, jsonb) TO authenticated;
