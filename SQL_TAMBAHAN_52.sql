-- SQL_TAMBAHAN_52: Papan Jualan Pekerja Hari Ini + Baucar Harian (Netto Cash Ditangan)
--
-- 1) Papan jualan pekerja hari ini — pemilik & SEMUA pekerja boleh lihat jumlah
-- jualan (transaksi status='selesai') setiap pekerja untuk hari semasa, papar di
-- Dashboard bawah kad Kehadiran. RLS profiles tak benarkan pekerja baca profil
-- pekerja lain (hanya "profil sendiri" + pemilik baca semua) — jadi guna RPC
-- SECURITY DEFINER yang HANYA dedah nama + jumlah jualan (bukan emel/telefon),
-- bukan buka akses terus ke jadual profiles.
CREATE OR REPLACE FUNCTION public.papan_jualan_pekerja_hari_ini()
RETURNS TABLE(pekerja_id uuid, nama text, jumlah_jualan double precision, bilangan_transaksi bigint)
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT p.id, p.nama,
    COALESCE(SUM(t.jumlah) FILTER (WHERE t.status = 'selesai'), 0) AS jumlah_jualan,
    COUNT(t.id) FILTER (WHERE t.status = 'selesai') AS bilangan_transaksi
  FROM profiles p
  LEFT JOIN transaksi t ON t.created_by = p.id::text AND t.tarikh_masa::date = CURRENT_DATE
  WHERE p.role = 'pekerja'
  GROUP BY p.id, p.nama
  ORDER BY jumlah_jualan DESC, p.nama;
$function$;

GRANT EXECUTE ON FUNCTION public.papan_jualan_pekerja_hari_ini() TO authenticated;

-- 2) Baucar Harian — jana baucar upah SATU HARI untuk seorang pekerja, netto
-- terus dengan cash tunai yang dia dah kutip hari tu (kaedah_bayaran='tunai',
-- status='selesai'). Baki (upah - cash) itulah SAHAJA yang pemilik perlu
-- transfer — bukan upah penuh, sebab cash yang pekerja dah pegang dikira
-- sebahagian bayaran upah dia terus (elak serah-tangan cash berasingan).
ALTER TABLE baucar_bayaran ADD COLUMN IF NOT EXISTS tarikh date;
ALTER TABLE baucar_bayaran ADD COLUMN IF NOT EXISTS cash_ditangan double precision DEFAULT 0;
ALTER TABLE baucar_bayaran ADD COLUMN IF NOT EXISTS baki double precision;

CREATE OR REPLACE FUNCTION public.cipta_baucar_harian(p_pekerja_id uuid, p_tarikh date DEFAULT CURRENT_DATE)
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

  -- Upah harian: SUM(qty x upah_pekerja produk) untuk semua transaksi pekerja pada tarikh ni.
  -- Sama formula dengan jumlahUpahTransaksi() client-side: consignment yang belum
  -- disahkan jual = 0, guna items_terjual jika consignment sudah disahkan.
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

  -- Cash di tangan: transaksi TUNAI (fizikal, bukan transfer/hutang) berstatus selesai pada tarikh ni.
  SELECT COALESCE(SUM(t.jumlah), 0) INTO v_cash
  FROM transaksi t
  WHERE t.created_by = p_pekerja_id::text AND t.tarikh_masa::date = p_tarikh
    AND t.kaedah_bayaran = 'tunai' AND t.status = 'selesai';

  v_baki := v_upah - v_cash;

  SELECT id INTO v_sedia_id FROM baucar_bayaran
    WHERE pekerja_id = p_pekerja_id AND kategori = 'upah_harian' AND tarikh = p_tarikh;

  IF v_sedia_id IS NOT NULL THEN
    UPDATE baucar_bayaran SET jumlah = v_upah, cash_ditangan = v_cash, baki = v_baki
      WHERE id = v_sedia_id AND status = 'draf'; -- baucar diluluskan/dibayar dikekalkan, tak ditimpa
    RETURN v_sedia_id;
  END IF;

  v_id := gen_random_uuid()::text;
  v_no_siri := 'PV-' || extract(year from now())::text || '-' || lpad(nextval('baucar_siri_seq')::text, 4, '0');
  INSERT INTO baucar_bayaran (id, no_siri, pekerja_id, kategori, bulan, tarikh, jumlah, cash_ditangan, baki, tujuan)
  VALUES (v_id, v_no_siri, p_pekerja_id, 'upah_harian', v_bulan, p_tarikh, v_upah, v_cash, v_baki,
    'Upah harian ' || to_char(p_tarikh, 'DD/MM/YYYY'));
  RETURN v_id;
END;
$function$;
