-- DILAKSANA pada projek Wafi 4 Nov 2026 (kelulusan Amirul: RM60/RM120/RM200 + RM25k->RM500; 180b = akaun pekerja milik pemilik dikecualikan).
-- SQL_TAMBAHAN_180: Insentif dua lapis (menggantikan versi 179 yang hanya bonus pasukan):
--  (1) Bonus INDIVIDU ikut kutipan bulanan pekerja (transaksi status 'selesai', waktu KL):
--      tetapan.insentif_tingkat = [{"min":12000,"bonus":60},{"min":14000,"bonus":120},{"min":16000,"bonus":200}]
--  (2) Bonus PASUKAN RM500 (insentif_bonus) bila jualan gabungan (bukan 'batal') >= insentif_sasaran (RM25k),
--      dibahagi sama rata antara pekerja aktif.
-- insentif_bulanan() dikemas kini (tandatangan sama, jsonb); SELECT agregat sahaja.
ALTER TABLE tetapan ADD COLUMN IF NOT EXISTS insentif_tingkat jsonb
  DEFAULT '[{"min":12000,"bonus":60},{"min":14000,"bonus":120},{"min":16000,"bonus":200}]'::jsonb;

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
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Perlu log masuk'; END IF;
  v_tamat := (v_mula + interval '1 month')::date;
  SELECT * INTO v_t FROM tetapan WHERE id = 1;
  SELECT COALESCE(SUM(jumlah),0) INTO v_jualan FROM transaksi
    WHERE status <> 'batal'
      AND (tarikh_masa AT TIME ZONE 'Asia/Kuala_Lumpur')::date >= v_mula
      AND (tarikh_masa AT TIME ZONE 'Asia/Kuala_Lumpur')::date < v_tamat;
  SELECT COUNT(*) INTO v_bil FROM profiles WHERE role = 'pekerja' AND status = 'aktif'
    AND nama NOT IN (SELECT nama FROM profiles WHERE role = 'pemilik'); -- akaun pekerja milik pemilik sendiri tidak dikira
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
    'sasaran', v_t.insentif_sasaran,
    'bonus', v_t.insentif_bonus,
    'jualan', ROUND(v_jualan, 2),
    'tercapai', v_jualan >= COALESCE(v_t.insentif_sasaran, 0) AND COALESCE(v_t.insentif_sasaran, 0) > 0,
    'baki', GREATEST(COALESCE(v_t.insentif_sasaran, 0) - v_jualan, 0),
    'bil_pekerja', v_bil,
    'bonus_seorang', CASE WHEN v_bil > 0 THEN ROUND((v_t.insentif_bonus / v_bil)::numeric, 2) ELSE v_t.insentif_bonus END,
    'pekerja', v_pekerja
  );
END $$;
REVOKE ALL ON FUNCTION insentif_bulanan(date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION insentif_bulanan(date) TO authenticated;
