-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 107: Diskaun invois AUTO dilucuthak (jumlah naik ke
-- harga penuh, hutang kedai turut naik) sekiranya melepasi tarikh
-- akhir bayaran (tarikh_akhir_bayaran) yang ditetapkan.
--
-- Disahkan bersama pemilik: bila invois berdiskaun lewat due, jumlah
-- SEBENAR tertunggak (transaksi.jumlah) DAN kedai.hutang naik
-- automatik ke harga penuh (diskaun_peratus jadi 0) — bukan sekadar
-- amaran paparan. diskaun_dilucuthak jadi flag idempoten (elak cron
-- ulang tambah selisih yg sama setiap kali jalan).
--
-- Consignment TAK terjejas (guna status hutang di belakang tabir tapi
-- model bayar-ikut-jualan sendiri, tiada diskaun_peratus konvensional
-- yg sama makna). Transaksi yg dah 'selesai' (dibayar) sebelum due pun
-- tak terjejas (WHERE status='hutang' sahaja).
-- ═══════════════════════════════════════════════════════════

ALTER TABLE public.transaksi ADD COLUMN IF NOT EXISTS diskaun_dilucuthak boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION public.lucuthak_diskaun_lewat_bayar()
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
  t RECORD;
  v_selisih double precision;
BEGIN
  FOR t IN
    SELECT * FROM transaksi
    WHERE status = 'hutang'
      AND kaedah_bayaran <> 'consignment'
      AND diskaun_peratus > 0
      AND NOT diskaun_dilucuthak
      AND tarikh_akhir_bayaran IS NOT NULL
      AND tarikh_akhir_bayaran < (now() AT TIME ZONE 'Asia/Kuala_Lumpur')::date
  LOOP
    v_selisih := t.jumlah_asal - t.jumlah; -- nilai diskaun yg dilucuthak (>=0)

    UPDATE transaksi SET
      jumlah = jumlah_asal,
      diskaun_peratus = 0,
      diskaun_dilucuthak = true
    WHERE id = t.id;

    IF t.kedai_id IS NOT NULL AND v_selisih > 0 THEN
      UPDATE kedai SET hutang = hutang + v_selisih WHERE id = t.kedai_id;
    END IF;
  END LOOP;
END;
$function$;

-- Jalankan sekali sehari, 00:30 waktu Malaysia (16:30 UTC hari sebelumnya) — lepas
-- tengah malam supaya "lewat" dikira ikut hari PENUH terakhir tarikh due, bukan
-- terlucut serta-merta pada tengah hari due itu sendiri.
SELECT cron.schedule(
  'lucuthak-diskaun-harian',
  '30 16 * * *',
  $$SELECT public.lucuthak_diskaun_lewat_bayar();$$
);
