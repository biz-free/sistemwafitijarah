-- SQL_TAMBAHAN_54: Baucar Harian kira SEMUA komponen upah (bukan upah penghantaran sahaja)
--
-- Sebelum ini cipta_baucar_harian() hanya kira upah penghantaran (qty x
-- upah_pekerja produk) untuk hari tu. Pemilik nak baucar harian kira SEKALI
-- semua yang pekerja wajib dapat: upah penghantaran + minyak kenderaan +
-- duit makan + bonus kedai baru (+ upah e-dagang).
--
-- Kadar minyak/makan/bonus (SETTINGS) disimpan di localStorage PELAYAR
-- pemilik sahaja — TIADA di database (lihat SETTINGS_DEF dalam
-- pengurusan.html) — jadi tak boleh dikira server-side dalam RPC ni.
-- Ikut corak SEDIA ADA yang sama seperti janaBaucarBulanIni() (kategori
-- petrol/upah/makan bulanan): client kira jumlah PENUH (guna formula SAMA
-- seperti pecahanHarian dalam renderUpahSaya()/renderLaporan(), supaya
-- konsisten dengan Laporan Bulanan), pemilik disahkan hantar (is_pemilik()
-- masih dikuatkuasakan), RPC hanya kira cash_ditangan (boleh disahkan
-- terus dari jadual transaksi) & baki secara bebas.
CREATE OR REPLACE FUNCTION public.cipta_baucar_harian(
  p_pekerja_id uuid, p_tarikh date DEFAULT CURRENT_DATE,
  p_jumlah double precision DEFAULT NULL::double precision,
  p_butiran jsonb DEFAULT NULL::jsonb
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_id text; v_no_siri text; v_sedia_id text;
  v_upah double precision := 0; v_cash double precision := 0; v_baki double precision;
  v_bulan text;
BEGIN
  IF NOT is_pemilik() THEN
    RAISE EXCEPTION 'Hanya pemilik boleh jana baucar harian';
  END IF;

  v_bulan := to_char(p_tarikh, 'YYYY-MM');

  IF p_jumlah IS NOT NULL THEN
    -- Jumlah PENUH (upah+minyak+makan+bonus+e-dagang) dikira client-side (pemilik
    -- yang disahkan) — sama macam kategori bulanan sedia ada, elak pendua-kira
    -- rate SETTINGS yang tiada di server.
    v_upah := p_jumlah;
  ELSE
    -- Fallback (panggilan lama/langsung tanpa p_jumlah): upah penghantaran sahaja.
    SELECT COALESCE(SUM(
      (SELECT COALESCE(SUM((item->>'qty')::numeric * COALESCE(s.upah_pekerja, 0)), 0)
       FROM jsonb_array_elements(
         CASE WHEN t.kaedah_bayaran = 'consignment' AND NOT COALESCE(t.jualan_disahkan, false)
              THEN '[]'::jsonb
              ELSE COALESCE(t.items_terjual, t.items)
         END
       ) item
       LEFT JOIN stok s ON s.id = item->>'stokId')
    ), 0) INTO v_upah
    FROM transaksi t
    WHERE t.created_by = p_pekerja_id::text AND t.tarikh_masa::date = p_tarikh;
  END IF;

  -- Cash di tangan: transaksi TUNAI (fizikal, bukan transfer/hutang) berstatus selesai pada tarikh ni.
  SELECT COALESCE(SUM(t.jumlah), 0) INTO v_cash
  FROM transaksi t
  WHERE t.created_by = p_pekerja_id::text AND t.tarikh_masa::date = p_tarikh
    AND t.kaedah_bayaran = 'tunai' AND t.status = 'selesai';

  v_baki := v_upah - v_cash;

  SELECT id INTO v_sedia_id FROM baucar_bayaran
    WHERE pekerja_id = p_pekerja_id AND kategori = 'upah_harian' AND tarikh = p_tarikh;

  IF v_sedia_id IS NOT NULL THEN
    UPDATE baucar_bayaran SET jumlah = v_upah, cash_ditangan = v_cash, baki = v_baki,
      butiran = COALESCE(p_butiran, butiran)
      WHERE id = v_sedia_id AND status = 'draf'; -- baucar diluluskan/dibayar dikekalkan, tak ditimpa
    RETURN v_sedia_id;
  END IF;

  v_id := gen_random_uuid()::text;
  v_no_siri := 'PV-' || extract(year from now())::text || '-' || lpad(nextval('baucar_siri_seq')::text, 4, '0');
  INSERT INTO baucar_bayaran (id, no_siri, pekerja_id, kategori, bulan, tarikh, jumlah, cash_ditangan, baki, tujuan, butiran)
  VALUES (v_id, v_no_siri, p_pekerja_id, 'upah_harian', v_bulan, p_tarikh, v_upah, v_cash, v_baki,
    'Upah harian ' || to_char(p_tarikh, 'DD/MM/YYYY'), p_butiran);
  RETURN v_id;
END;
$function$;
