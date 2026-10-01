-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 158: Diskaun kecil 2% untuk PRE-ORDER bawah minima (RM500)
-- yang dibayar serta-merta, bermula 1 Oktober 2026.
--
-- Syarat: SQL_TAMBAHAN_156 mesti dijalankan DAHULU (tambah lajur
-- tetapan.diskaun_segera_kecil_peratus & tetapan.skim_hutang_mula).
--
-- validasi_harga_pre_order() (versi asal SQL 56) AUTHORITATIVE — timpa nilai dari
-- pesan.html. Perubahan hanya satu blok baharu: bila jumlah BAWAH minima dan
-- bayar_metod = cod (tunai) / transfer / billplz (online serta-merta), dan tarikh
-- pesanan (waktu Malaysia) >= skim_hutang_mula -> diskaun = diskaun_segera_kecil_peratus.
-- Consignment kekal 0%. Pesanan >= minima kekal kadar sedia ada (cod 5% / transfer & billplz 10%).
-- billplz-create-bill mengambil jumlah_selepas_diskaun, jadi amaun bil turut dikecilkan.
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.validasi_harga_pre_order()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  item jsonb;
  harga_item float;
  sub float := 0;
  t_minima float; t_diskaun float; t_diskaun_cod float; t_had_consignment float;
  t_skim_mula date; t_diskaun_kecil float;
  peratus float := 0;
BEGIN
  FOR item IN SELECT * FROM jsonb_array_elements(COALESCE(NEW.items, '[]'::jsonb)) LOOP
    SELECT harga_jual INTO harga_item FROM stok WHERE id = item->>'stokId';
    IF harga_item IS NULL THEN
      RAISE EXCEPTION 'Produk % tidak wujud atau telah dipadam', item->>'stokId';
    END IF;
    sub := sub + harga_item * (item->>'qty')::int;
  END LOOP;

  SELECT minima_transfer, diskaun_peratus, diskaun_cod_peratus, consignment_limit,
         skim_hutang_mula, diskaun_segera_kecil_peratus
    INTO t_minima, t_diskaun, t_diskaun_cod, t_had_consignment,
         t_skim_mula, t_diskaun_kecil
    FROM tetapan WHERE id = 1;

  -- Consignment cuma dibenarkan bawah had — turunkan automatik ke COD jika melebihi
  IF NEW.bayar_metod = 'consignment' AND sub >= COALESCE(t_had_consignment, 300) THEN
    NEW.bayar_metod := 'cod';
  END IF;

  IF sub >= COALESCE(t_minima, 500) THEN
    IF NEW.bayar_metod = 'cod' THEN peratus := COALESCE(t_diskaun_cod, 0);
    -- Billplz = bayaran online serta-merta, samakan dengan transfer
    ELSIF NEW.bayar_metod IN ('transfer', 'billplz') THEN peratus := COALESCE(t_diskaun, 0);
    END IF;
  ELSIF NEW.bayar_metod IN ('cod', 'transfer', 'billplz')
        AND t_skim_mula IS NOT NULL
        AND (now() AT TIME ZONE 'Asia/Kuala_Lumpur')::date >= t_skim_mula THEN
    -- Bawah minima: bayar tunai / transfer / online serta-merta dapat diskaun kecil (SQL 158)
    peratus := COALESCE(t_diskaun_kecil, 0);
  END IF;

  NEW.jumlah_asal := sub;
  NEW.diskaun_peratus := peratus;
  NEW.jumlah_selepas_diskaun := sub * (1 - peratus/100);
  NEW.status := 'baru';

  RETURN NEW;
END;
$function$;
