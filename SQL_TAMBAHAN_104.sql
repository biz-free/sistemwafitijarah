-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 104: Resit & hutang consignment AUTO KEMASKINI
-- ikut produk yang BETUL-BETUL terjual, bila pekerja sahkan jualan.
--
-- Punca masalah: submit_penghantaran rekod jumlah PENUH (semua barang
-- dihantar) & terus tambah ke kedai.hutang sejak awal (model consignment
-- "letak barang dulu"). sahkan_jualan_konsainan (SQL_TAMBAHAN_28) cuma
-- simpan items_terjual utk KIRA UPAH pekerja sahaja (jumlahUpahTransaksi
-- guna items_terjual, bukan items) — tapi transaksi.jumlah & kedai.hutang
-- tak pernah dibetulkan bila ada barang tak terjual/dipulangkan. Akibatnya
-- resit (renderResit) & hutang kedai kekal papar jumlah PENUH konsainan
-- buat selama-lamanya, walaupun kedai dah pulangkan barang tak laku —
-- salah dari segi model bayar-ikut-jualan.
--
-- Fix: bila jualan disahkan, kira semula jumlah/jumlah_asal transaksi
-- ikut items_terjual sahaja (kekalkan kadar diskaun asal), & betulkan
-- kedai.hutang ikut SELISIH (barang tak terjual = bukan hutang). Resit
-- (renderResit di pengurusan.html) baca terus t.jumlah/t.items_terjual
-- secara LIVE bila dipaparkan/dicetak — jadi auto kemaskini tanpa perlu
-- jana resit baharu.
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.sahkan_jualan_konsainan(p_transaksi_id text, p_items_terjual jsonb)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
  v_trx RECORD;
  item jsonb;
  v_qty_asal int;
  v_qty_jual int;
  v_harga double precision;
  v_jumlah_asal_terjual double precision := 0;
  v_jumlah_terjual double precision;
  v_selisih double precision;
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
    SELECT (i->>'qty')::int, (i->>'harga')::double precision INTO v_qty_asal, v_harga
      FROM jsonb_array_elements(v_trx.items) i WHERE i->>'stokId' = item->>'stokId';
    IF v_qty_asal IS NULL OR v_qty_jual IS NULL OR v_qty_jual < 0 OR v_qty_jual > v_qty_asal THEN
      RAISE EXCEPTION 'Kuantiti terjual tidak sah untuk produk %', item->>'stokId';
    END IF;
    v_jumlah_asal_terjual := v_jumlah_asal_terjual + (COALESCE(v_harga, 0) * v_qty_jual);
  END LOOP;

  -- Kekalkan kadar diskaun asal (jika ada) pada jumlah yang dah dikecilkan ikut
  -- barang terjual sahaja — sepadan dgn cara jumlah asal dikira semasa hantar.
  v_jumlah_terjual := v_jumlah_asal_terjual * (1 - COALESCE(v_trx.diskaun_peratus, 0) / 100);
  v_selisih := v_trx.jumlah - v_jumlah_terjual; -- >=0 sentiasa (qty terjual <= qty dihantar)

  UPDATE transaksi SET
    items_terjual = p_items_terjual,
    jualan_disahkan = true,
    disahkan_oleh = auth.uid(),
    disahkan_pada = now(),
    jumlah = v_jumlah_terjual,
    jumlah_asal = v_jumlah_asal_terjual
  WHERE id = p_transaksi_id;

  -- Barang tak terjual = dipulangkan, bukan hutang — betulkan kedai.hutang ikut
  -- selisih (sama pattern spt padam_transaksi_kedai, SQL_TAMBAHAN_86).
  IF v_trx.status = 'hutang' AND v_trx.kedai_id IS NOT NULL AND v_selisih <> 0 THEN
    UPDATE kedai SET hutang = GREATEST(0, hutang - v_selisih) WHERE id = v_trx.kedai_id;
  END IF;
END;
$function$;
