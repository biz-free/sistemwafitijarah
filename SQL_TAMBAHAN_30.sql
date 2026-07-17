-- ═══════════════════════════════════════════════════════════
--  WAFI TIJARAH TRADING — SQL TAMBAHAN #30
--  Jalankan SEKALI sahaja dalam Supabase SQL Editor.
--  (Padam transaksi kedai: bug pembetulan — stok yang telah ditolak
--   semasa penghantaran asal kini dipulangkan ke stok gudang pusat
--   apabila pemilik padam rekod transaksi, elak stok "hilang". Hutang
--   kedai yang berkaitan transaksi tu turut dilaraskan balik.)
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION padam_transaksi_kedai(p_id text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_trx RECORD; item jsonb;
BEGIN
  IF NOT is_pemilik() THEN RAISE EXCEPTION 'Hanya pemilik boleh padam transaksi'; END IF;

  SELECT * INTO v_trx FROM transaksi WHERE id = p_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Transaksi tidak dijumpai'; END IF;

  FOR item IN SELECT * FROM jsonb_array_elements(v_trx.items) LOOP
    UPDATE stok SET stok = stok + (item->>'qty')::int WHERE id = item->>'stokId';
  END LOOP;

  IF v_trx.status = 'hutang' AND v_trx.kedai_id IS NOT NULL THEN
    UPDATE kedai SET hutang = GREATEST(0, hutang - v_trx.jumlah) WHERE id = v_trx.kedai_id;
  END IF;

  DELETE FROM transaksi WHERE id = p_id;
END;
$$;
GRANT EXECUTE ON FUNCTION padam_transaksi_kedai(text) TO authenticated;
