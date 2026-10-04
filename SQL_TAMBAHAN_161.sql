-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 161: Kaedah kiraan minyak BAHARU "GPS Trail Tertapis" untuk baucar
-- harian (upah_harian) — pemilik PILIH GPS atau P2P bila luluskan di Telegram.
--
-- PUNCA (arahan Amirul 2026-10-04): kiraan minyak sedia ada (P2P — nearest-neighbour
-- antara titik kehadiran & pin kedai) dikira client-side di app pekerja dan
-- bergantung pada pin kedai. Pemilik mahu pilihan kedua berasaskan jejak GPS
-- sebenar (jadual gps_track, ~1 titik/min) sebagai perbandingan semasa lulus.
--
-- PENYELESAIAN:
--   1. tetapan.minyak_gps_rm_km (lalai RM0.50/km) — kadar BAHARU berasingan drpd
--      minyak_rm_km (P2P).
--   2. kira_minyak_gps_baucar(p_baucar_id) — kira SERVER-SIDE (tak percaya client):
--        • semua sesi kehadiran pekerja pada tarikh baucar (ikut tarikh thumb in, waktu MY)
--        • titik gps_track tersusun ikut masa
--        • TAPISAN lonjakan signal: setiap titik dibanding dgn TITIK SAH TERAKHIR (anchor),
--          bukan titik sebelum — jika kelajuan implisit > 120 km/j, titik itu dilangkau
--          (tidak dikira, anchor kekal) supaya perjalanan sebenar A->C masih dikira bila
--          titik tersasar B terletak di antaranya. Tiada interpolasi.
--        • jumlah_gps = jumlah baucar SEDIA ADA - butiran.minyak (P2P) + km_gps x kadar GPS
--          (kekal sebarang pelarasan yg sudah ditolak dlm jumlah; bonus bukan sebahagian jumlah)
--        • jumlah_gps = NULL jika data GPS tak mencukupi (<2 titik) atau butiran.minyak tiada
--          -> butang GPS tidak ditawarkan (elak pekerja dapat minyak RM0 kerana tiada data)
--   3. telegram_putuskan_baucar_gps(chat, id) — dipanggil webhook bila 🛰️ GPS ditekan:
--      kira SEMULA di server, kemas kini jumlah/baki/butiran(minyak,km; asal disimpan
--      sbg minyak_p2p/km_p2p, kaedah_minyak='gps') + status 'diluluskan'. Pulangkan teks
--      SAMA seperti kelulusan biasa ("Baucar harian diluluskan ✅") supaya pemakluman
--      WhatsApp Team Sales tidak berubah. Pencetus pemakluman_keputusan (SQL 153) tercetus
--      seperti biasa kerana status berubah draf -> diluluskan.
-- Kedua-dua fungsi baharu HANYA boleh dipanggil oleh service_role (Edge Function).
-- ═══════════════════════════════════════════════════════════

ALTER TABLE public.tetapan ADD COLUMN IF NOT EXISTS minyak_gps_rm_km double precision DEFAULT 0.50;
UPDATE public.tetapan SET minyak_gps_rm_km = COALESCE(minyak_gps_rm_km, 0.50) WHERE id = 1;

CREATE OR REPLACE FUNCTION public.kira_minyak_gps_baucar(p_baucar_id text)
RETURNS TABLE(km_gps double precision, minyak_gps double precision, jumlah_gps double precision, jumlah_p2p double precision, bil_titik integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_pekerja uuid; v_tarikh date; v_kategori text; v_jumlah double precision; v_minyak_p2p double precision;
  v_kadar double precision;
  v_km double precision := 0; v_titik integer := 0;
  s RECORD; p RECORD;
  a_ada boolean; a_lat double precision; a_lng double precision; a_masa timestamptz;
  d double precision; jam double precision;
BEGIN
  SELECT pekerja_id, tarikh, kategori, jumlah, NULLIF(butiran->>'minyak', '')::double precision
    INTO v_pekerja, v_tarikh, v_kategori, v_jumlah, v_minyak_p2p
    FROM baucar_bayaran WHERE id = p_baucar_id;

  IF v_pekerja IS NULL OR v_kategori IS DISTINCT FROM 'upah_harian' THEN
    RETURN QUERY SELECT NULL::double precision, NULL::double precision, NULL::double precision, v_jumlah, 0;
    RETURN;
  END IF;

  SELECT COALESCE(minyak_gps_rm_km, 0.50) INTO v_kadar FROM tetapan WHERE id = 1;

  FOR s IN
    SELECT id FROM kehadiran
    WHERE pekerja_id = v_pekerja
      AND (thumb_in_masa AT TIME ZONE 'Asia/Kuala_Lumpur')::date = v_tarikh
    ORDER BY thumb_in_masa
  LOOP
    a_ada := false;
    FOR p IN
      SELECT lat, lng, tarikh_masa FROM gps_track
      WHERE kehadiran_id = s.id AND lat IS NOT NULL AND lng IS NOT NULL
      ORDER BY tarikh_masa, id
    LOOP
      v_titik := v_titik + 1;
      IF NOT a_ada THEN
        a_lat := p.lat; a_lng := p.lng; a_masa := p.tarikh_masa; a_ada := true;
        CONTINUE;
      END IF;

      jam := extract(epoch FROM (p.tarikh_masa - a_masa)) / 3600.0;
      IF jam <= 0 THEN CONTINUE; END IF; -- cap masa sama/terbalik: langkau

      d := 2 * 6371 * asin(sqrt(
             sin(radians(p.lat - a_lat) / 2) ^ 2 +
             cos(radians(a_lat)) * cos(radians(p.lat)) * sin(radians(p.lng - a_lng) / 2) ^ 2));

      IF d / jam > 120 THEN CONTINUE; END IF; -- lonjakan signal: langkau titik ini, anchor kekal

      v_km := v_km + d;
      a_lat := p.lat; a_lng := p.lng; a_masa := p.tarikh_masa;
    END LOOP;
  END LOOP;

  IF v_titik < 2 OR v_minyak_p2p IS NULL OR v_jumlah IS NULL THEN
    RETURN QUERY SELECT v_km, NULL::double precision, NULL::double precision, v_jumlah, v_titik;
  ELSE
    RETURN QUERY SELECT
      v_km,
      ROUND((v_km * v_kadar)::numeric, 2)::double precision,
      GREATEST(0, ROUND((v_jumlah - v_minyak_p2p + v_km * v_kadar)::numeric, 2))::double precision,
      v_jumlah,
      v_titik;
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.telegram_putuskan_baucar_gps(p_admin_chat_id bigint, p_id text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_admin_user_id uuid;
  b RECORD; g RECORD;
BEGIN
  SELECT user_id INTO v_admin_user_id FROM telegram_admin WHERE chat_id = p_admin_chat_id AND aktif = true;
  IF v_admin_user_id IS NULL THEN
    RAISE EXCEPTION 'Chat Telegram ini tidak didaftarkan sebagai pemilik atau tidak aktif';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = v_admin_user_id AND role = 'pemilik') THEN
    RAISE EXCEPTION 'Akaun berkaitan bukan pemilik';
  END IF;

  SELECT * INTO b FROM baucar_bayaran WHERE id = p_id AND kategori = 'upah_harian' AND status = 'draf' FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Baucar tidak dijumpai atau bukan lagi draf (mungkin sudah diluluskan/dibayar/dibatalkan)';
  END IF;

  SELECT * INTO g FROM kira_minyak_gps_baucar(p_id);
  IF g.jumlah_gps IS NULL THEN
    RAISE EXCEPTION 'Data GPS tidak mencukupi untuk baucar ini — sila guna Lulus / P2P';
  END IF;

  UPDATE baucar_bayaran SET
    jumlah = g.jumlah_gps,
    baki = g.jumlah_gps - COALESCE(cash_ditangan, 0),
    butiran = COALESCE(butiran, '{}'::jsonb) || jsonb_build_object(
      'minyak', g.minyak_gps, 'km', g.km_gps,
      'minyak_p2p', butiran->'minyak', 'km_p2p', butiran->'km',
      'kaedah_minyak', 'gps'),
    status = 'diluluskan', diluluskan_oleh = v_admin_user_id, diluluskan_pada = now()
  WHERE id = p_id;

  RETURN 'Baucar harian diluluskan ✅';
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.kira_minyak_gps_baucar(text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.telegram_putuskan_baucar_gps(bigint, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.kira_minyak_gps_baucar(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.telegram_putuskan_baucar_gps(bigint, text) TO service_role;
