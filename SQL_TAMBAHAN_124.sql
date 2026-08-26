-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 124: Baiki `kira_cash_dipegang_pekerja()` — hutang yang
-- dibayar TUNAI (kedai & peribadi) sebelum ni TAK dikira sebagai cash
-- dipegang pekerja langsung.
--
-- Punca: fungsi cuma imbas `transaksi` yang ASALNYA kaedah_bayaran='tunai'.
-- Bila hutang (kaedah_bayaran='hutang' pada rekod asal) dibayar kemudian
-- secara tunai (melalui permohonan_bayaran_hutang, disahkan pemilik),
-- lajur kaedah_bayaran pada transaksi tak pernah ditukar — jadi cash
-- sebenar yang pekerja kutip terus HILANG drpd pengiraan "cash dipegang".
-- Ini turut menjejaskan tolakan cash pada Bonus Kedai Terkumpul
-- (bayar_bonus_kedai_terkumpul, SQL_TAMBAHAN_112) sebab guna fungsi sama.
--
-- Pembetulan: gabungkan (UNION) cash drpd transaksi tunai+selesai DENGAN
-- cash drpd hutang yang disahkan dibayar tunai, ikut hari kalendar
-- (Malaysia) yang sama, sebelum tolak baucar upah harian & serahan cash —
-- logik selebihnya (netting harian, tolak serahan) kekal sama.
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.kira_cash_dipegang_pekerja(p_pekerja_id uuid)
 RETURNS double precision
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH semua_cash AS (
    SELECT (tarikh_masa AT TIME ZONE 'Asia/Kuala_Lumpur')::date AS tarikh, jumlah
    FROM transaksi
    WHERE created_by = p_pekerja_id::text AND kaedah_bayaran = 'tunai' AND status = 'selesai'
    UNION ALL
    SELECT (created_at AT TIME ZONE 'Asia/Kuala_Lumpur')::date AS tarikh, jumlah
    FROM permohonan_bayaran_hutang
    WHERE pekerja_id = p_pekerja_id AND kaedah_bayaran = 'tunai' AND status = 'disahkan'
  ),
  cash_harian AS (
    SELECT tarikh, SUM(jumlah) AS cash_hari FROM semua_cash GROUP BY 1
  ),
  belum_diselesai AS (
    SELECT COALESCE(SUM(GREATEST(0, ch.cash_hari - COALESCE(bh.jumlah, 0))), 0) AS jumlah
    FROM cash_harian ch
    LEFT JOIN baucar_bayaran bh ON bh.pekerja_id = p_pekerja_id AND bh.kategori = 'upah_harian'
      AND bh.tarikh = ch.tarikh AND bh.status <> 'dibatalkan'
  ),
  diserahkan AS (
    SELECT COALESCE(SUM(jumlah), 0) AS jumlah FROM serahan_cash
    WHERE pekerja_id = p_pekerja_id AND status <> 'ditolak'
  )
  SELECT (SELECT jumlah FROM belum_diselesai) - (SELECT jumlah FROM diserahkan);
$function$;
