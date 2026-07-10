-- ═══════════════════════════════════════════════════════════
--  WAFI TIJARAH TRADING — SQL TAMBAHAN #18
--  Jalankan SEKALI sahaja dalam Supabase SQL Editor.
--  (KESELAMATAN — sambungan SQL_TAMBAHAN_17.sql, kali ini untuk
--   borang repeat-order kedai B2B di pesan.html)
-- ═══════════════════════════════════════════════════════════
--  MASALAH SAMA seperti pesanan_edagang: dasar RLS untuk pre_order
--  ialah FOR INSERT WITH CHECK (true) — sesiapa yang tahu anon key
--  (terdedah dalam kod pesan.html) boleh hantar pre-order dengan
--  jumlah_asal/diskaun_peratus/jumlah_selepas_diskaun APA SAHAJA,
--  atau pilih bayar_metod='consignment' walaupun jumlah melebihi had
--  yang ditetapkan pemilik (consignment_limit).
--
--  NOTA: pre_order tidak sama risiko dengan pesanan_edagang — jumlah
--  di sini hanya PAPARAN jangkaan untuk staff (staf rekod jualan
--  sebenar secara berasingan di "Rekod Baru" semasa penghantaran
--  sebenar, bukan automatik daripada pre_order). Tapi papar jumlah
--  yang salah masih boleh mengelirukan staf, dan langkau had
--  consignment ialah pintasan dasar perniagaan sebenar — jadi tetap
--  wajar dibaiki.
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION validasi_harga_pre_order()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  item jsonb;
  harga_item float;
  sub float := 0;
  t_minima float; t_diskaun float; t_diskaun_cod float; t_had_consignment float;
  peratus float := 0;
BEGIN
  FOR item IN SELECT * FROM jsonb_array_elements(COALESCE(NEW.items, '[]'::jsonb)) LOOP
    SELECT harga_jual INTO harga_item FROM stok WHERE id = item->>'stokId';
    IF harga_item IS NULL THEN
      RAISE EXCEPTION 'Produk % tidak wujud atau telah dipadam', item->>'stokId';
    END IF;
    sub := sub + harga_item * (item->>'qty')::int;
  END LOOP;

  SELECT minima_transfer, diskaun_peratus, diskaun_cod_peratus, consignment_limit
    INTO t_minima, t_diskaun, t_diskaun_cod, t_had_consignment
    FROM tetapan WHERE id = 1;

  -- Consignment cuma dibenarkan bawah had — turunkan automatik ke COD jika melebihi
  IF NEW.bayar_metod = 'consignment' AND sub >= COALESCE(t_had_consignment, 300) THEN
    NEW.bayar_metod := 'cod';
  END IF;

  IF sub >= COALESCE(t_minima, 500) THEN
    IF NEW.bayar_metod = 'cod' THEN peratus := COALESCE(t_diskaun_cod, 0);
    ELSIF NEW.bayar_metod = 'transfer' THEN peratus := COALESCE(t_diskaun, 0);
    END IF;
  END IF;

  NEW.jumlah_asal := sub;
  NEW.diskaun_peratus := peratus;
  NEW.jumlah_selepas_diskaun := sub * (1 - peratus/100);
  NEW.status := 'baru';

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validasi_harga_pre_order ON pre_order;
CREATE TRIGGER trg_validasi_harga_pre_order
  BEFORE INSERT ON pre_order
  FOR EACH ROW EXECUTE FUNCTION validasi_harga_pre_order();
