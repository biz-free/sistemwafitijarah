-- ============================================================
-- SQL TAMBAHAN 170: Segarkan cash_ditangan/baki baucar harian DRAF automatik
-- bila bayaran hutang tunai disahkan / dibetulkan (susulan SQL 169).
-- Masalah: baucar draf dijana (mis. waktu thumb out), kemudian pemilik lulus bayaran hutang
-- tunai pada hari yang sama -> baucar ketinggalan. Trigger ini kira semula cash draf sahaja.
-- Hanya baucar berstatus 'draf' disentuh; diluluskan/dibayar TIDAK diubah.
-- Formula SAMA dgn cipta_baucar_harian & kira_cash_dipegang_pekerja:
--   cash = transaksi tunai selesai (hari itu) + permohonan_bayaran_hutang tunai disahkan (hari itu, ikut created_at MYT)
-- ============================================================

CREATE OR REPLACE FUNCTION public.segarkan_cash_baucar_draf(p_pekerja_id uuid, p_tarikh date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_cash double precision;
BEGIN
  IF p_pekerja_id IS NULL OR p_tarikh IS NULL THEN RETURN; END IF;

  SELECT COALESCE((SELECT SUM(t.jumlah) FROM transaksi t
                    WHERE t.created_by = p_pekerja_id::text
                      AND (t.tarikh_masa AT TIME ZONE 'Asia/Kuala_Lumpur')::date = p_tarikh
                      AND t.kaedah_bayaran = 'tunai' AND t.status = 'selesai'), 0)
       + COALESCE((SELECT SUM(p.jumlah) FROM permohonan_bayaran_hutang p
                    WHERE p.pekerja_id = p_pekerja_id AND p.kaedah_bayaran = 'tunai' AND p.status = 'disahkan'
                      AND (p.created_at AT TIME ZONE 'Asia/Kuala_Lumpur')::date = p_tarikh), 0)
    INTO v_cash;

  UPDATE baucar_bayaran
     SET cash_ditangan = v_cash, baki = jumlah - v_cash
   WHERE pekerja_id = p_pekerja_id AND kategori = 'upah_harian' AND tarikh = p_tarikh
     AND status = 'draf'
     AND (cash_ditangan IS DISTINCT FROM v_cash);
END;
$function$;

CREATE OR REPLACE FUNCTION public.trg_segarkan_baucar_selepas_bayaran_hutang()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- Gagal senyap: jangan sekali-kali halang kelulusan bayaran hutang kerana baucar.
  BEGIN
    PERFORM segarkan_cash_baucar_draf(NEW.pekerja_id, (NEW.created_at AT TIME ZONE 'Asia/Kuala_Lumpur')::date);
    IF OLD.pekerja_id IS DISTINCT FROM NEW.pekerja_id THEN
      PERFORM segarkan_cash_baucar_draf(OLD.pekerja_id, (OLD.created_at AT TIME ZONE 'Asia/Kuala_Lumpur')::date);
    END IF;
  EXCEPTION WHEN others THEN
    RAISE WARNING '[segarkan_baucar_draf] gagal utk %: %', NEW.id, SQLERRM;
  END;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.segarkan_cash_baucar_draf(uuid, date) FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_segarkan_baucar_bayaran_hutang ON public.permohonan_bayaran_hutang;
CREATE TRIGGER trg_segarkan_baucar_bayaran_hutang
  AFTER UPDATE OF status, kaedah_bayaran, pekerja_id, jumlah ON public.permohonan_bayaran_hutang
  FOR EACH ROW
  WHEN (OLD.status = 'disahkan' OR NEW.status = 'disahkan')
  EXECUTE FUNCTION public.trg_segarkan_baucar_selepas_bayaran_hutang();

-- Pengesahan (SELECT sahaja) selepas dilaksana — baucar draf yang cash-nya tidak sepadan (dijangka 0 baris):
--   select b.id, b.tarikh, b.cash_ditangan from baucar_bayaran b where b.status='draf' and b.kategori='upah_harian'
--     and abs(b.cash_ditangan - (
--       coalesce((select sum(t.jumlah) from transaksi t where t.created_by=b.pekerja_id::text and (t.tarikh_masa at time zone 'Asia/Kuala_Lumpur')::date=b.tarikh and t.kaedah_bayaran='tunai' and t.status='selesai'),0)
--      +coalesce((select sum(p.jumlah) from permohonan_bayaran_hutang p where p.pekerja_id=b.pekerja_id and p.kaedah_bayaran='tunai' and p.status='disahkan' and (p.created_at at time zone 'Asia/Kuala_Lumpur')::date=b.tarikh),0))) > 0.005;
