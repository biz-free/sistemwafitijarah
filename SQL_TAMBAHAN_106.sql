-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 106: Pemilik boleh betulkan JUMLAH ASAL transaksi yang
-- tersilap key-in (cth: salah kuantiti/harga) — tanpa perlu padam &
-- minta pekerja hantar semula. Kes sebenar: AAA Teguh Mutiara Ambangan
-- Heights (K7208384).
--
-- Betulkan JUMLAH ASAL (sebelum diskaun) sahaja — jumlah akhir dikira
-- semula server-side ikut kadar diskaun_peratus sedia ada (konsisten
-- dgn cara jumlah dikira di seluruh sistem: jumlah = jumlah_asal *
-- (1-diskaun/100)). kedai.hutang dilaraskan ikut SELISIH jumlah akhir
-- (bukan jumlah asal), sebab hutang sentiasa jejak jumlah SEBENAR
-- tertunggak (selepas diskaun), bukan harga sebelum diskaun.
--
-- Consignment TAK guna RPC ni (ada mekanisme sendiri — Kemaskini
-- Jualan/sahkan_jualan_konsainan — kira jumlah dari items, bukan
-- medan jumlah_asal terus).
-- ═══════════════════════════════════════════════════════════

ALTER TABLE public.transaksi ADD COLUMN IF NOT EXISTS jumlah_diedit_oleh uuid REFERENCES auth.users(id);
ALTER TABLE public.transaksi ADD COLUMN IF NOT EXISTS jumlah_diedit_pada timestamptz;
-- Simpan jumlah_asal ASLI (sebelum sebarang edit) sekali sahaja, utk rujukan audit —
-- COALESCE dlm RPC pastikan medan ni cuma diisi pada edit PERTAMA, tak ditimpa lagi.
ALTER TABLE public.transaksi ADD COLUMN IF NOT EXISTS jumlah_asal_original double precision;

CREATE OR REPLACE FUNCTION public.edit_jumlah_transaksi(p_id text, p_jumlah_asal_baru double precision, p_nota text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
  v_trx RECORD;
  v_jumlah_baru double precision;
  v_selisih double precision;
BEGIN
  IF NOT is_pemilik() THEN RAISE EXCEPTION 'Hanya pemilik boleh edit jumlah transaksi'; END IF;
  IF p_jumlah_asal_baru IS NULL OR p_jumlah_asal_baru < 0 THEN RAISE EXCEPTION 'Jumlah mesti 0 atau lebih'; END IF;

  SELECT * INTO v_trx FROM transaksi WHERE id = p_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Transaksi tidak dijumpai'; END IF;
  IF v_trx.kaedah_bayaran = 'consignment' THEN
    RAISE EXCEPTION 'Consignment guna Kemaskini Jualan utk betulkan jumlah, bukan edit terus';
  END IF;

  v_jumlah_baru := p_jumlah_asal_baru * (1 - COALESCE(v_trx.diskaun_peratus, 0) / 100);
  v_selisih := v_jumlah_baru - v_trx.jumlah;

  UPDATE transaksi SET
    jumlah_asal = p_jumlah_asal_baru,
    jumlah = v_jumlah_baru,
    jumlah_asal_original = COALESCE(jumlah_asal_original, v_trx.jumlah_asal),
    jumlah_diedit_oleh = auth.uid(),
    jumlah_diedit_pada = now(),
    nota = CASE WHEN p_nota IS NOT NULL AND p_nota <> '' THEN COALESCE(nota || E'\n', '') || '[Edit jumlah oleh pemilik] ' || p_nota ELSE nota END
  WHERE id = p_id;

  IF v_trx.status = 'hutang' AND v_trx.kedai_id IS NOT NULL AND v_selisih <> 0 THEN
    UPDATE kedai SET hutang = GREATEST(0, hutang + v_selisih) WHERE id = v_trx.kedai_id;
  END IF;
END;
$function$;
