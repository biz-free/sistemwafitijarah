-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 112: Bonus Kedai Terkumpul matang kini TOLAK cash
-- dipegang pekerja dahulu — baki sahaja dibayar.
--
-- Sebelum ini: bayar_bonus_kedai_terkumpul() bayar PENUH jumlah bonus matang
-- tanpa mengira cash tunai yang pekerja masih PEGANG (belum diserah kepada
-- pemilik). Ini bermakna pekerja boleh terima bonus tunai SEKALI GUS masih
-- pegang cash jualan yang sepatutnya diserah — dua nilai berasingan sedangkan
-- sepatutnya bonus tu boleh terus offset cash yang tertunggak dahulu.
--
-- Kini: bonus matang - cash dipegang (kira_cash_dipegang_pekerja, port SQL drpd
-- fungsi client kiraCashDipegang() sedia ada) = baki yang BENAR-BENAR dibayar.
-- Bahagian yang "ditolak" utk offset cash direkod sbg serahan_cash automatik
-- (status='disahkan' terus, bukan serahan fizikal) supaya kiraan cash dipegang
-- pekerja betul utk pengiraan seterusnya (elak dikira 2x). Jika cash dipegang
-- >= bonus matang, bonus tetap ditanda 'dibayar' (nilainya sudah offset cash
-- sepenuhnya) tapi TIADA baucar RM0 dijana.
-- ═══════════════════════════════════════════════════════════

-- ── Port SQL drpd fungsi client kiraCashDipegang() (pengurusan.html) — MESTI
-- kekal logik sama drpd client supaya paparan "CASH DIPEGANG SEKARANG" pekerja
-- padan dgn apa yg benar-benar ditolak semasa bayaran bonus. ──
CREATE OR REPLACE FUNCTION public.kira_cash_dipegang_pekerja(p_pekerja_id uuid)
RETURNS double precision
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  WITH cash_harian AS (
    SELECT (tarikh_masa AT TIME ZONE 'Asia/Kuala_Lumpur')::date AS tarikh, SUM(jumlah) AS cash_hari
    FROM transaksi
    WHERE created_by = p_pekerja_id::text AND kaedah_bayaran = 'tunai' AND status = 'selesai'
    GROUP BY 1
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
$$;
GRANT EXECUTE ON FUNCTION public.kira_cash_dipegang_pekerja(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.bayar_bonus_kedai_terkumpul(p_pekerja_id uuid, p_gabung_baucar boolean DEFAULT false)
RETURNS TABLE(jumlah_asal double precision, cash_ditolak double precision, jumlah_dibayar double precision)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public' AS $function$
DECLARE
  v_jumlah double precision;
  v_cash_dipegang double precision;
  v_tolak double precision;
  v_bayar double precision;
  v_tarikh date;
  v_baucar_id text;
  v_no_siri text;
  v_serahan_id text;
BEGIN
  IF NOT is_pemilik() THEN RAISE EXCEPTION 'Hanya pemilik boleh sahkan bayaran bonus'; END IF;

  SELECT COALESCE(SUM(jumlah),0) INTO v_jumlah FROM bonus_kedai_baru
    WHERE pekerja_id = p_pekerja_id AND status = 'belum_dibayar' AND tarikh_matang <= CURRENT_DATE;
  IF v_jumlah <= 0 THEN RAISE EXCEPTION 'Tiada bonus matang untuk dibayar'; END IF;

  v_cash_dipegang := kira_cash_dipegang_pekerja(p_pekerja_id);
  v_tolak := LEAST(v_jumlah, GREATEST(0::double precision, v_cash_dipegang));
  v_bayar := v_jumlah - v_tolak;

  v_tarikh := (now() AT TIME ZONE 'Asia/Kuala_Lumpur')::date;

  -- Tolak cash dipegang DAHULU drpd bonus matang — rekod sbg serahan cash
  -- auto-disahkan (bukan serahan fizikal, diselesaikan terus melalui potongan
  -- bonus) supaya kira_cash_dipegang_pekerja() betul utk pengiraan seterusnya.
  IF v_tolak > 0 THEN
    v_serahan_id := 'SC' || substr(replace(gen_random_uuid()::text,'-',''),1,8);
    INSERT INTO serahan_cash (id, pekerja_id, jumlah, nota, status, disahkan_oleh, disahkan_pada)
    VALUES (v_serahan_id, p_pekerja_id, v_tolak::numeric, 'Ditolak automatik drpd Bonus Kedai Terkumpul matang', 'disahkan', auth.uid(), now());
  END IF;

  v_baucar_id := NULL;
  IF v_bayar > 0 THEN
    IF p_gabung_baucar THEN
      SELECT id INTO v_baucar_id FROM baucar_bayaran WHERE pekerja_id = p_pekerja_id AND kategori = 'upah_harian' AND tarikh = v_tarikh;
      IF v_baucar_id IS NOT NULL THEN
        UPDATE baucar_bayaran SET jumlah = jumlah + v_bayar, baki = COALESCE(baki,0) + v_bayar,
          butiran = COALESCE(butiran,'{}'::jsonb) || jsonb_build_object('bonusKedaiDibayar', v_bayar, 'bonusKedaiAsal', v_jumlah, 'bonusKedaiCashDitolak', v_tolak)
          WHERE id = v_baucar_id;
      ELSE
        v_baucar_id := gen_random_uuid()::text;
        v_no_siri := 'PV-' || extract(year from now())::text || '-' || lpad(nextval('baucar_siri_seq')::text, 4, '0');
        INSERT INTO baucar_bayaran (id, no_siri, pekerja_id, kategori, bulan, tarikh, jumlah, cash_ditangan, baki, tujuan, butiran)
        VALUES (v_baucar_id, v_no_siri, p_pekerja_id, 'upah_harian', to_char(v_tarikh,'YYYY-MM'), v_tarikh, v_bayar, 0, v_bayar,
          'Upah harian ' || to_char(v_tarikh,'DD/MM/YYYY'), jsonb_build_object('bonusKedaiDibayar', v_bayar, 'bonusKedaiAsal', v_jumlah, 'bonusKedaiCashDitolak', v_tolak));
      END IF;
    ELSE
      v_baucar_id := gen_random_uuid()::text;
      v_no_siri := 'PV-' || extract(year from now())::text || '-' || lpad(nextval('baucar_siri_seq')::text, 4, '0');
      INSERT INTO baucar_bayaran (id, no_siri, pekerja_id, kategori, bulan, tarikh, jumlah, tujuan, butiran)
      VALUES (v_baucar_id, v_no_siri, p_pekerja_id, 'bonus_kedai', to_char(v_tarikh,'YYYY-MM'), v_tarikh, v_bayar,
        'Bonus Kedai Baru Terkumpul (' || to_char(v_tarikh,'DD/MM/YYYY') || ')',
        jsonb_build_object('bonusKedaiAsal', v_jumlah, 'bonusKedaiCashDitolak', v_tolak));
    END IF;
  END IF;
  -- v_bayar = 0 (cash dipegang menutupi SEPENUHNYA bonus matang): tiada baucar
  -- RM0 dijana, tapi bonus tetap ditanda 'dibayar' — nilainya sudah digunakan
  -- utk offset cash (lihat rekod serahan_cash di atas), bukan hilang percuma.

  UPDATE bonus_kedai_baru SET status = 'dibayar', dibayar_pada = now(), baucar_id = v_baucar_id
    WHERE pekerja_id = p_pekerja_id AND status = 'belum_dibayar' AND tarikh_matang <= CURRENT_DATE;

  RETURN QUERY SELECT v_jumlah, v_tolak, v_bayar;
END;
$function$;
