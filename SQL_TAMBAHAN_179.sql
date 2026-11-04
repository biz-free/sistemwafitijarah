-- DILAKSANA pada projek Wafi 4 Nov 2026 (kelulusan Amirul: "Kemaskini semua sistem").
-- SQL_TAMBAHAN_179: Insentif sasaran jualan bulanan (berkuat kuasa November 2026).
-- Jualan gabungan semua pekerja sebulan >= sasaran -> bonus (dibahagi sama rata).
-- (a) 4 lajur tetapan (tiada data sedia ada diubah; baris id=1 dapat nilai lalai).
-- (b) insentif_bulanan(p_bulan): SELECT agregat sahaja (jualan tak termasuk status 'batal',
--     bulan ikut waktu Kuala Lumpur). SECURITY DEFINER supaya pekerja nampak jumlah gabungan
--     walaupun RLS hanya benarkan baris sendiri; tiada baris/pelanggan didedahkan.
ALTER TABLE tetapan ADD COLUMN IF NOT EXISTS insentif_aktif boolean DEFAULT true;
ALTER TABLE tetapan ADD COLUMN IF NOT EXISTS insentif_sasaran double precision DEFAULT 25000;
ALTER TABLE tetapan ADD COLUMN IF NOT EXISTS insentif_bonus double precision DEFAULT 500;
ALTER TABLE tetapan ADD COLUMN IF NOT EXISTS insentif_mula date DEFAULT '2026-11-01';

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
  SELECT COUNT(*) INTO v_bil FROM profiles WHERE role = 'pekerja' AND status = 'aktif';
  SELECT COALESCE(jsonb_agg(jsonb_build_object('nama', nama, 'jualan', jualan) ORDER BY jualan DESC), '[]'::jsonb) INTO v_pekerja
  FROM (
    SELECT COALESCE(p.singkatan, p.nama) AS nama, ROUND(SUM(t.jumlah)::numeric, 2) AS jualan
    FROM transaksi t JOIN profiles p ON p.id::text = t.created_by
    WHERE t.status <> 'batal' AND p.role = 'pekerja'
      AND (t.tarikh_masa AT TIME ZONE 'Asia/Kuala_Lumpur')::date >= v_mula
      AND (t.tarikh_masa AT TIME ZONE 'Asia/Kuala_Lumpur')::date < v_tamat
    GROUP BY 1
  ) x;
  RETURN jsonb_build_object(
    'bulan', v_mula,
    'berkuatkuasa', COALESCE(v_t.insentif_aktif, false) AND v_mula >= COALESCE(v_t.insentif_mula, v_mula),
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
