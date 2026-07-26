-- SQL_TAMBAHAN_57: Auto-lepas voucher & kod rujukan bila pembelian gagal/dibatalkan
--
-- MASALAH 1: Bila pembeli guna kod voucher, trigger validasi_harga_pesanan_edagang
-- terus menaikkan baucar.bilangan_guna dan memasukkan rekod baucar_guna semasa
-- pesanan DICIPTA (belum bayar lagi). Jika bayaran akhirnya gagal atau pemilik
-- batalkan pesanan, kuota voucher tu kekal "terpakai" — pembeli tak boleh guna
-- semula walaupun tak pernah dapat barang. Sebelum ini pemilik terpaksa tekan
-- butang "🔓 Bebaskan Voucher" satu per satu secara manual.
--
-- MASALAH 2: validasi_rujukan() menyekat kod rujukan kepada "pelanggan baharu
-- (pesanan pertama)" dengan menyemak SEBARANG pesanan sedia ada. Oleh sebab
-- data pembeli sengaja DIKEKALKAN walaupun gagal bayar (lihat SQL_TAMBAHAN_50 /
-- batalkanEdagang), satu pesanan gagal terus menghalang pembeli itu daripada
-- guna kod rujukan kawan buat selama-lamanya. Pesanan gagal/dibatalkan kini
-- tidak lagi dikira sebagai "pernah membeli".

CREATE OR REPLACE FUNCTION public.lepas_promosi_pesanan_gagal()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- Hanya bertindak pada peralihan KEPADA gagal/dibatalkan, dan hanya jika
  -- masih ada kod terpaut. Selepas dilepaskan kod_baucar jadi NULL, jadi
  -- kemaskini status berulang kali tidak akan tolak kuota dua kali.
  IF (NEW.status_bayaran = 'gagal' OR NEW.status_pesanan = 'dibatalkan')
     AND NEW.kod_baucar IS NOT NULL AND NEW.kod_baucar <> '' THEN

    DELETE FROM baucar_guna
      WHERE kod = NEW.kod_baucar AND pesanan_id = NEW.id;

    UPDATE baucar
      SET bilangan_guna = GREATEST(0, COALESCE(bilangan_guna, 0) - 1)
      WHERE kod = NEW.kod_baucar;

    -- Kosongkan supaya pesanan tak lagi menuntut voucher itu (dan elak
    -- pelepasan berulang), tapi diskaun yang sudah direkod dikekalkan
    -- sebagai jejak audit sejarah pesanan.
    NEW.kod_baucar := NULL;
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_lepas_promosi_pesanan_gagal ON pesanan_edagang;
CREATE TRIGGER trg_lepas_promosi_pesanan_gagal
  BEFORE UPDATE ON pesanan_edagang
  FOR EACH ROW EXECUTE FUNCTION lepas_promosi_pesanan_gagal();

-- Kod rujukan: pesanan yang gagal/dibatalkan tidak menjadikan seseorang itu
-- "bukan pelanggan baharu" lagi.
CREATE OR REPLACE FUNCTION public.validasi_rujukan(p_kod_rujukan text, p_telefon_pembeli text)
 RETURNS TABLE(sah boolean, mesej text, diskaun_peratus double precision)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_telefon_rujukan text;
  v_telefon_pembeli text;
  v_aktif boolean;
  v_peratus float;
  v_wujud boolean;
BEGIN
  SELECT rujukan_aktif, rujukan_diskaun_kawan_peratus INTO v_aktif, v_peratus FROM tetapan WHERE id = 1;
  IF NOT COALESCE(v_aktif, true) THEN
    RETURN QUERY SELECT false, 'Program rujukan tidak aktif', NULL::float; RETURN;
  END IF;

  v_telefon_rujukan := regexp_replace(trim(p_kod_rujukan), '[^0-9]', '', 'g');
  v_telefon_pembeli := regexp_replace(trim(p_telefon_pembeli), '[^0-9]', '', 'g');
  IF v_telefon_rujukan = '' THEN
    RETURN QUERY SELECT false, 'Kod rujukan tidak sah', NULL::float; RETURN;
  END IF;
  IF v_telefon_rujukan = v_telefon_pembeli THEN
    RETURN QUERY SELECT false, 'Tidak boleh guna nombor sendiri sebagai kod rujukan', NULL::float; RETURN;
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM pesanan_edagang
    WHERE regexp_replace(pelanggan_telefon, '[^0-9]', '', 'g') = v_telefon_rujukan AND status_bayaran = 'disahkan'
  ) INTO v_wujud;

  IF NOT v_wujud THEN
    SELECT EXISTS(
      SELECT 1 FROM rujukan_manual
      WHERE regexp_replace(telefon, '[^0-9]', '', 'g') = v_telefon_rujukan AND aktif = true
    ) INTO v_wujud;
  END IF;

  IF NOT v_wujud THEN
    RETURN QUERY SELECT false, 'Kod rujukan tidak dijumpai', NULL::float; RETURN;
  END IF;

  -- Pesanan gagal/dibatalkan TIDAK dikira — pembeli yang tak pernah berjaya
  -- membeli masih layak sebagai pelanggan baharu.
  SELECT EXISTS(
    SELECT 1 FROM pesanan_edagang
    WHERE regexp_replace(pelanggan_telefon, '[^0-9]', '', 'g') = v_telefon_pembeli
      AND COALESCE(status_bayaran, '') <> 'gagal'
      AND COALESCE(status_pesanan, '') <> 'dibatalkan'
  ) INTO v_wujud;
  IF v_wujud THEN
    RETURN QUERY SELECT false, 'Kod rujukan hanya untuk pelanggan baharu (pesanan pertama)', NULL::float; RETURN;
  END IF;

  RETURN QUERY SELECT true, format('Kod rujukan sah — diskaun %s%% untuk pesanan pertama anda!', v_peratus), v_peratus;
END; $function$;
