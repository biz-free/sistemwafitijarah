-- SQL_TAMBAHAN_49: QR Bayaran + Bukti Resit Wajib di Tab Hantar
--
-- Tambah lajur resit_bukti_url pada transaksi (gambar resit/bukti fizikal
-- penghantaran, wajib diisi sebelum penghantar boleh "Sahkan & Rekod
-- Penghantaran" untuk destinasi kedai — lihat pengurusan.html submitHantar()).
-- QR bank + butiran akaun (sedia ada di Tetapan Pre-Order & Diskaun) kini
-- turut dipaparkan terus dalam borang Hantar bila kaedah bayaran = Transfer,
-- supaya penghantar boleh tunjuk terus kepada kedai untuk imbas & bayar.

ALTER TABLE transaksi ADD COLUMN IF NOT EXISTS resit_bukti_url text;

CREATE OR REPLACE FUNCTION public.submit_penghantaran(
  p_id text, p_kedai_id text, p_items jsonb, p_jumlah double precision,
  p_status text, p_nota text, p_resit text, p_jarak_km double precision DEFAULT 0,
  p_nama_pembeli text DEFAULT NULL::text, p_kaedah_bayaran text DEFAULT 'tunai'::text,
  p_jumlah_asal double precision DEFAULT NULL::double precision, p_diskaun_peratus double precision DEFAULT 0,
  p_resit_bukti_url text DEFAULT NULL::text
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE item jsonb;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid()) THEN
    RAISE EXCEPTION 'Tidak dibenarkan';
  END IF;

  FOR item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    UPDATE stok_pekerja SET kuantiti = kuantiti - (item->>'qty')::int
      WHERE pekerja_id = auth.uid() AND stok_id = item->>'stokId' AND kuantiti >= (item->>'qty')::int;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Stok bawaan anda tidak mencukupi untuk %', item->>'stokId';
    END IF;
  END LOOP;

  INSERT INTO transaksi (id, kedai_id, nama_pembeli, items, jumlah, status, nota, resit, jarak_km, created_by, kaedah_bayaran, jumlah_asal, diskaun_peratus, jualan_disahkan, resit_bukti_url)
  VALUES (p_id, p_kedai_id, p_nama_pembeli, p_items, p_jumlah, p_status, p_nota, p_resit, p_jarak_km, auth.uid()::text, p_kaedah_bayaran, COALESCE(p_jumlah_asal, p_jumlah), p_diskaun_peratus, (p_kaedah_bayaran <> 'consignment'), p_resit_bukti_url);

  UPDATE kedai SET
    hutang = hutang + (CASE WHEN p_status = 'hutang' THEN p_jumlah ELSE 0 END),
    last_visit = CURRENT_DATE::text
  WHERE id = p_kedai_id;
END;
$function$;
