-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 64: Auto-jana Baucar Harian selepas Thumb Out.
--
-- Sebelum ini kadar minyak/makan/bonus kedai baru (SETTINGS) hanya
-- wujud di localStorage PELAYAR PEMILIK — pekerja lain (peranti lain)
-- tiada cara dapatkan kadar sebenar utk kira upah sendiri. Pindahkan
-- ke jadual "tetapan" (sedia ada, sejagat, boleh baca semua orang)
-- supaya SETIAP akaun (pekerja & pemilik) dapat kadar SAMA.
--
-- cipta_baucar_harian(uuid, date, float8, jsonb) dilonggarkan: pekerja
-- kini boleh jana draf baucar harian untuk DIRI SENDIRI sahaja (bukan
-- pekerja lain). Definisi disalin TERUS daripada versi LIVE production
-- (bukan fail SQL_TAMBAHAN_54 lama) — versi live sudah ada pembetulan
-- zon waktu Malaysia (AT TIME ZONE 'Asia/Kuala_Lumpur') yang tiada
-- dalam fail arkib lama; hanya syarat kebenaran yang diubah.
--
-- ⚠️ NOTA KESELAMATAN (ditemui & dibetulkan SEMASA membina ciri ini):
-- Percubaan pertama guna syarat "p_pekerja_id <> auth.uid()" ada bug
-- logik NULL — bila dipanggil TANPA log masuk, auth.uid() = NULL, dan
-- "<uuid> <> NULL" menilai kepada NULL (bukan TRUE), lalu "IF NULL
-- THEN" dalam PL/pgSQL tidak dianggap benar — pengecualian TIDAK
-- dilontar, membenarkan pemanggil TANPA LOG MASUK terus panggil fungsi
-- ini! Disahkan boleh dieksploitasi melalui panggilan RPC anonymous
-- sebenar sebelum dibetulkan (rekod voucher sebenar berjaya dipulangkan
-- balik, walaupun kekangan "AND status = 'draf'" pada UPDATE kebetulan
-- elak sebarang kerosakan data pada ujian tersebut). Turut ditemui:
-- Supabase projek ini bagi EXECUTE kepada peranan "anon" pada SEMUA
-- fungsi baru secara lalai (bukan hanya PUBLIC — grant terus kepada
-- anon, REVOKE ... FROM PUBLIC tidak cukup) — jadi checks di ATAS
-- (bukan grant) adalah pertahanan sebenar. Fungsi ambil_stok_pekerja
-- (SQL_TAMBAHAN_63) turut didapati LANGSUNG TIADA semakan log masuk —
-- dibetulkan sekali di bawah. Kedua-dua dibetulkan dengan "IF auth.uid()
-- IS NULL THEN RAISE EXCEPTION" eksplisit di awal fungsi.
-- ═══════════════════════════════════════════════════════════

ALTER TABLE tetapan ADD COLUMN minyak_rm_km double precision NOT NULL DEFAULT 0.50;
ALTER TABLE tetapan ADD COLUMN makan_rm_hari double precision NOT NULL DEFAULT 10.00;
ALTER TABLE tetapan ADD COLUMN upah_kedai_baru_bayar double precision NOT NULL DEFAULT 10.00;
ALTER TABLE tetapan ADD COLUMN upah_kedai_baru_consignment double precision NOT NULL DEFAULT 2.00;

CREATE OR REPLACE FUNCTION public.cipta_baucar_harian(
  p_pekerja_id uuid, p_tarikh date DEFAULT NULL::date,
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
  v_bulan text; v_tarikh date;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Log masuk diperlukan';
  END IF;
  IF NOT is_pemilik() AND p_pekerja_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Pekerja hanya boleh jana baucar harian untuk diri sendiri';
  END IF;

  v_tarikh := COALESCE(p_tarikh, (now() AT TIME ZONE 'Asia/Kuala_Lumpur')::date);
  v_bulan := to_char(v_tarikh, 'YYYY-MM');

  IF p_jumlah IS NOT NULL THEN
    v_upah := p_jumlah;
  ELSE
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
    WHERE t.created_by = p_pekerja_id::text
      AND (t.tarikh_masa AT TIME ZONE 'Asia/Kuala_Lumpur')::date = v_tarikh;
  END IF;

  SELECT COALESCE(SUM(t.jumlah), 0) INTO v_cash
  FROM transaksi t
  WHERE t.created_by = p_pekerja_id::text
    AND (t.tarikh_masa AT TIME ZONE 'Asia/Kuala_Lumpur')::date = v_tarikh
    AND t.kaedah_bayaran = 'tunai' AND t.status = 'selesai';

  v_baki := v_upah - v_cash;

  SELECT id INTO v_sedia_id FROM baucar_bayaran
    WHERE pekerja_id = p_pekerja_id AND kategori = 'upah_harian' AND tarikh = v_tarikh;

  IF v_sedia_id IS NOT NULL THEN
    UPDATE baucar_bayaran SET jumlah = v_upah, cash_ditangan = v_cash, baki = v_baki,
      butiran = COALESCE(p_butiran, butiran)
      WHERE id = v_sedia_id AND status = 'draf';
    RETURN v_sedia_id;
  END IF;

  v_id := gen_random_uuid()::text;
  v_no_siri := 'PV-' || extract(year from now())::text || '-' || lpad(nextval('baucar_siri_seq')::text, 4, '0');
  INSERT INTO baucar_bayaran (id, no_siri, pekerja_id, kategori, bulan, tarikh, jumlah, cash_ditangan, baki, tujuan, butiran)
  VALUES (v_id, v_no_siri, p_pekerja_id, 'upah_harian', v_bulan, v_tarikh, v_upah, v_cash, v_baki,
    'Upah harian ' || to_char(v_tarikh, 'DD/MM/YYYY'), p_butiran);
  RETURN v_id;
END;
$function$;

-- ambil_stok_pekerja (SQL_TAMBAHAN_63) tiada LANGSUNG semakan log masuk — anon boleh
-- kurangkan stok gudang sebenar (pekerja_id di stok_pekerja boleh NULL). Tambah
-- semakan eksplisit di awal, selebihnya kekal sama seperti SQL_TAMBAHAN_63.
CREATE OR REPLACE FUNCTION public.ambil_stok_pekerja(p_stok_id text, p_qty int) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_nama text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Log masuk diperlukan'; END IF;
  IF p_qty <= 0 THEN RAISE EXCEPTION 'Kuantiti mesti lebih 0'; END IF;
  UPDATE stok SET stok = stok - p_qty WHERE id = p_stok_id AND stok >= p_qty;
  IF NOT FOUND THEN RAISE EXCEPTION 'Stok gudang tidak mencukupi'; END IF;
  INSERT INTO stok_pekerja (pekerja_id, stok_id, kuantiti) VALUES (auth.uid(), p_stok_id, p_qty)
    ON CONFLICT (pekerja_id, stok_id) DO UPDATE SET kuantiti = stok_pekerja.kuantiti + p_qty;
  SELECT nama INTO v_nama FROM stok WHERE id = p_stok_id;
  INSERT INTO serahan_produk (id, pekerja_id, stok_id, stok_nama, kuantiti, jenis, status)
  VALUES (gen_random_uuid()::text, auth.uid(), p_stok_id, COALESCE(v_nama, p_stok_id), p_qty, 'ambil', 'disahkan');
END;
$$;
