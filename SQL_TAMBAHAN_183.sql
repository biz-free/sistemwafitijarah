-- DILAKSANA pada projek Wafi 4 Nov 2026 (kelulusan Amirul: tangga bonus pasukan RM30k->RM100, RM40k->RM250, RM50k->RM500 SETIAP pekerja).
-- SQL_TAMBAHAN_183: bonus pasukan kini bertingkat (tetapan.insentif_tingkat_pasukan, jsonb [{min,bonus}]).
-- insentif_sasaran/insentif_bonus (179) dikekalkan tetapi tidak lagi digunakan oleh kiraan.
-- insentif_bulanan() ditulis semula: pulang juga tingkat_pasukan, bonus_pasukan (diperoleh), seterusnya_pasukan, bonus_seterusnya.
ALTER TABLE tetapan ADD COLUMN IF NOT EXISTS insentif_tingkat_pasukan jsonb
  DEFAULT '[{"min":30000,"bonus":100},{"min":40000,"bonus":250},{"min":50000,"bonus":500}]'::jsonb;

CREATE OR REPLACE FUNCTION insentif_bulanan(p_bulan date DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_mula date := date_trunc('month', COALESCE(p_bulan, (now() AT TIME ZONE 'Asia/Kuala_Lumpur')::date))::date;
  v_tamat date;
  v_t tetapan%ROWTYPE;
  v_jualan numeric;
  v_bil int;
  v_pekerja jsonb;
  v_dapat numeric;
  v_depan numeric;
  v_depan_bonus numeric;
  v_puncak numeric;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Perlu log masuk'; END IF;
  v_tamat := (v_mula + interval '1 month')::date;
  SELECT * INTO v_t FROM tetapan WHERE id = 1;
  SELECT COALESCE(SUM(jumlah),0) INTO v_jualan FROM transaksi
    WHERE status <> 'batal'
      AND (tarikh_masa AT TIME ZONE 'Asia/Kuala_Lumpur')::date >= v_mula
      AND (tarikh_masa AT TIME ZONE 'Asia/Kuala_Lumpur')::date < v_tamat;
  SELECT COUNT(*) INTO v_bil FROM profiles WHERE role = 'pekerja' AND status = 'aktif'
    AND nama NOT IN (SELECT nama FROM profiles WHERE role = 'pemilik');
  SELECT MAX((e->>'bonus')::numeric) FILTER (WHERE v_jualan >= (e->>'min')::numeric),
         MIN((e->>'min')::numeric) FILTER (WHERE v_jualan < (e->>'min')::numeric),
         MAX((e->>'min')::numeric)
    INTO v_dapat, v_depan, v_puncak
    FROM jsonb_array_elements(COALESCE(v_t.insentif_tingkat_pasukan, '[]'::jsonb)) e;
  SELECT (e->>'bonus')::numeric INTO v_depan_bonus
    FROM jsonb_array_elements(COALESCE(v_t.insentif_tingkat_pasukan, '[]'::jsonb)) e
    WHERE (e->>'min')::numeric = v_depan LIMIT 1;
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'nama', x.nama, 'saya', x.saya, 'jualan', x.jualan, 'kutipan', x.kutipan,
      'bonus', COALESCE(b.bonus, 0), 'seterusnya', b.seterusnya) ORDER BY x.kutipan DESC), '[]'::jsonb)
  INTO v_pekerja
  FROM (
    SELECT p.id = auth.uid() AS saya, COALESCE(p.singkatan, p.nama) AS nama,
      ROUND(COALESCE(SUM(t.jumlah) FILTER (WHERE t.status <> 'batal'), 0)::numeric, 2) AS jualan,
      ROUND(COALESCE(SUM(t.jumlah) FILTER (WHERE t.status = 'selesai'), 0)::numeric, 2) AS kutipan
    FROM profiles p
    LEFT JOIN transaksi t ON t.created_by = p.id::text
      AND (t.tarikh_masa AT TIME ZONE 'Asia/Kuala_Lumpur')::date >= v_mula
      AND (t.tarikh_masa AT TIME ZONE 'Asia/Kuala_Lumpur')::date < v_tamat
    WHERE p.role = 'pekerja' AND p.status = 'aktif'
      AND p.nama NOT IN (SELECT nama FROM profiles WHERE role = 'pemilik')
    GROUP BY p.id, p.singkatan, p.nama
  ) x
  LEFT JOIN LATERAL (
    SELECT MAX((e->>'bonus')::numeric) FILTER (WHERE x.kutipan >= (e->>'min')::numeric) AS bonus,
           MIN((e->>'min')::numeric) FILTER (WHERE x.kutipan < (e->>'min')::numeric) AS seterusnya
    FROM jsonb_array_elements(COALESCE(v_t.insentif_tingkat, '[]'::jsonb)) e
  ) b ON true;
  RETURN jsonb_build_object(
    'bulan', v_mula,
    'berkuatkuasa', COALESCE(v_t.insentif_aktif, false) AND v_mula >= COALESCE(v_t.insentif_mula, v_mula),
    'tingkat', COALESCE(v_t.insentif_tingkat, '[]'::jsonb),
    'tingkat_pasukan', COALESCE(v_t.insentif_tingkat_pasukan, '[]'::jsonb),
    'sasaran', COALESCE(v_puncak, 0),
    'jualan', ROUND(v_jualan, 2),
    'bonus_pasukan', COALESCE(v_dapat, 0),
    'seterusnya_pasukan', v_depan,
    'bonus_seterusnya', v_depan_bonus,
    'bil_pekerja', v_bil,
    'pekerja', v_pekerja
  );
END $$;
REVOKE ALL ON FUNCTION insentif_bulanan(date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION insentif_bulanan(date) TO authenticated;
