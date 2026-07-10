-- ═══════════════════════════════════════════════════════════
--  WAFI TIJARAH TRADING — SQL TAMBAHAN #21
--  Jalankan SEKALI sahaja dalam Supabase SQL Editor.
--  (1. Kunci peranti GPS semasa Thumb In — elak 2 peranti hantar GPS
--      serentak; peranti kedua ambil alih automatik jika peranti
--      pertama senyap >3 minit (bateri habis, dll).
--   2. Kaedah Bayaran "Online Transfer" di Rekod Baru + diskaun %
--      ikut kaedah bayaran, guna semula kadar sedia ada di Tetapan
--      Pre-Order & Diskaun.)
-- ═══════════════════════════════════════════════════════════

-- ═══ 1. Kunci peranti GPS ═══
ALTER TABLE kehadiran ADD COLUMN IF NOT EXISTS gps_device_id text;
ALTER TABLE kehadiran ADD COLUMN IF NOT EXISTS gps_last_ping timestamptz;

-- ═══ 2. Kaedah bayaran & diskaun untuk Rekod Baru (jadual transaksi) ═══
ALTER TABLE transaksi ADD COLUMN IF NOT EXISTS kaedah_bayaran text DEFAULT 'tunai';
ALTER TABLE transaksi ADD COLUMN IF NOT EXISTS jumlah_asal float;
ALTER TABLE transaksi ADD COLUMN IF NOT EXISTS diskaun_peratus float DEFAULT 0;

-- Kemaskini fungsi submit_penghantaran — sertakan kaedah bayaran & diskaun.
-- Parameter baru DEFAULT supaya panggilan lama (jika ada) tak pecah.
CREATE OR REPLACE FUNCTION submit_penghantaran(
  p_id text, p_kedai_id text, p_items jsonb, p_jumlah float,
  p_status text, p_nota text, p_resit text, p_jarak_km float DEFAULT 0,
  p_nama_pembeli text DEFAULT NULL,
  p_kaedah_bayaran text DEFAULT 'tunai', p_jumlah_asal float DEFAULT NULL, p_diskaun_peratus float DEFAULT 0
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
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

  INSERT INTO transaksi (id, kedai_id, nama_pembeli, items, jumlah, status, nota, resit, jarak_km, created_by, kaedah_bayaran, jumlah_asal, diskaun_peratus)
  VALUES (p_id, p_kedai_id, p_nama_pembeli, p_items, p_jumlah, p_status, p_nota, p_resit, p_jarak_km, auth.uid()::text, p_kaedah_bayaran, COALESCE(p_jumlah_asal, p_jumlah), p_diskaun_peratus);

  UPDATE kedai SET
    hutang = hutang + (CASE WHEN p_status = 'hutang' THEN p_jumlah ELSE 0 END),
    last_visit = CURRENT_DATE::text
  WHERE id = p_kedai_id;
END;
$$;
