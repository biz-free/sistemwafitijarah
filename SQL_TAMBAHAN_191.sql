-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 191: Pemilik boleh EDIT Tarikh & Masa transaksi terus di
-- Tempahan > Transaksi Kedai (butang "Edit Masa"). Kes guna: transaksi
-- direkod lewat/awal dan perlu dilaraskan ikut masa sebenar.
-- Hanya tukar tarikh_masa — tiada kesan pada jumlah/hutang/stok.
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.edit_masa_transaksi(p_id text, p_masa_baru timestamptz)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT is_pemilik() THEN
    RAISE EXCEPTION 'Hanya pemilik boleh edit masa transaksi';
  END IF;
  IF p_masa_baru IS NULL THEN
    RAISE EXCEPTION 'Tarikh & masa mesti diisi';
  END IF;
  UPDATE transaksi SET tarikh_masa = p_masa_baru WHERE id = p_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Transaksi tidak dijumpai'; END IF;
END;
$function$;
