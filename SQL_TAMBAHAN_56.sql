-- SQL_TAMBAHAN_56: Bayaran online Billplz turut layak diskaun (pre-order)
--
-- BUG: validasi_harga_pre_order() hanya beri diskaun untuk bayar_metod
-- 'cod' dan 'transfer'. Kedai yang pilih "💳 Bayar Online" (Billplz) —
-- iaitu bayaran paling terjamin & serta-merta untuk syarikat — LANGSUNG
-- tak dapat diskaun, walaupun sepanduk promosi di pesan.html menjanjikan
-- potongan untuk "INSTANT TRANSFER/QR".
--
-- Trigger ini AUTHORITATIVE (timpa nilai dihantar client), jadi pembetulan
-- di pesan.html sahaja tidak mencukupi — mesti dibetulkan di sini juga.
-- Billplz diberi kadar yang SAMA dengan transfer (diskaun_peratus) kerana
-- kedua-duanya bayaran penuh serta-merta, bukan COD.
--
-- Nota: billplz-create-bill/index.ts mengambil jumlah_selepas_diskaun untuk
-- menetapkan amaun bil sebenar — jadi pembetulan ini terus menurunkan amaun
-- yang dicaj kepada kedai, bukan sekadar paparan.

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
    -- Billplz = bayaran online serta-merta, samakan dengan transfer
    ELSIF NEW.bayar_metod IN ('transfer', 'billplz') THEN peratus := COALESCE(t_diskaun, 0);
    END IF;
  END IF;

  NEW.jumlah_asal := sub;
  NEW.diskaun_peratus := peratus;
  NEW.jumlah_selepas_diskaun := sub * (1 - peratus/100);
  NEW.status := 'baru';

  RETURN NEW;
END;
$function$;
