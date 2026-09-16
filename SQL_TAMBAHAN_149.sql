-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 149: Papan Jualan Pekerja BULANAN (semua pekerja boleh
-- lihat jumlah jualan bulanan pekerja lain, bukan setakat sendiri)
--
-- Dashboard pekerja sedia ada dah ada "Jualan Pekerja Hari Ini"
-- (papan_jualan_pekerja_hari_ini) — kad baharu ni tambah paparan sama
-- tapi jumlahkan BULAN SEMASA (waktu Malaysia), diletak terus di bawah
-- kad harian tu dlm pengurusan.html.
--
-- Guna corak SAMA seperti fungsi harian: RPC SECURITY DEFINER (RLS
-- profiles tak benarkan pekerja baca profil pekerja lain terus — RPC
-- ni hanya dedah nama + jumlah jualan, bukan data sensitif spt no
-- telefon/alamat), dan kunci akses terus kpd authenticated SAHAJA drpd
-- awal — elak kebocoran anon/PUBLIC yg pernah berlaku pada fungsi
-- harian (rujuk SQL_TAMBAHAN_90/91, dibetulkan selepas get_advisors
-- kesan ia masih boleh dipanggil oleh anon walaupun grant eksplisit
-- dah dibuang, sbb grant PUBLIC lalai PostgreSQL bila fungsi dicipta).
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.papan_jualan_pekerja_bulanan()
RETURNS TABLE(pekerja_id uuid, nama text, jumlah_jualan double precision, bilangan_transaksi bigint)
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT p.id, p.nama,
    COALESCE(SUM(t.jumlah) FILTER (WHERE t.status = 'selesai'), 0) AS jumlah_jualan,
    COUNT(t.id) FILTER (WHERE t.status = 'selesai') AS bilangan_transaksi
  FROM profiles p
  LEFT JOIN transaksi t
    ON t.created_by = p.id::text
   AND date_trunc('month', t.tarikh_masa AT TIME ZONE 'Asia/Kuala_Lumpur')
       = date_trunc('month', now() AT TIME ZONE 'Asia/Kuala_Lumpur')
  WHERE p.role = 'pekerja'
  GROUP BY p.id, p.nama
  ORDER BY jumlah_jualan DESC, p.nama;
$function$;

REVOKE EXECUTE ON FUNCTION public.papan_jualan_pekerja_bulanan() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.papan_jualan_pekerja_bulanan() FROM anon;
GRANT EXECUTE ON FUNCTION public.papan_jualan_pekerja_bulanan() TO authenticated;
