-- ═══════════════════════════════════════════════════════════
--  WAFI TIJARAH TRADING — SQL TAMBAHAN #17
--  Jalankan SEKALI sahaja dalam Supabase SQL Editor.
--  (KESELAMATAN — WAJIB. Baiki pesanan_edagang boleh dipalsukan)
-- ═══════════════════════════════════════════════════════════
--  MASALAH: Dasar RLS sedia ada untuk pesanan_edagang ialah
--    FOR INSERT WITH CHECK (true)
--  — bermakna SESIAPA yang tahu anon key (kunci awam, terdedah dalam
--  kod index.html) boleh hantar INSERT terus ke jadual ini melalui
--  panggilan REST API, dengan harga item, kos penghantaran & status
--  bayaran APA SAHAJA yang mereka mahu — termasuk tetapkan
--  status_bayaran terus kepada 'disahkan' tanpa bayar langsung, atau
--  harga produk RM1000 ditetapkan sebagai RM0.01.
--
--  PENYELESAIAN: Trigger BEFORE INSERT yang kira SEMULA harga setiap
--  item daripada jadual `stok` sebenar (abaikan apa client hantar),
--  dan paksa status_bayaran sentiasa 'menunggu' pada penciptaan
--  pesanan — pengesahan sebenar HANYA boleh berlaku melalui staff
--  (RLS UPDATE sedia ada, perlukan profil staff) atau webhook Billplz
--  (service_role, X-Signature disahkan).
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION validasi_harga_pesanan_edagang()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  item jsonb;
  item_baru jsonb := '[]'::jsonb;
  harga_sebenar float;
  sub float := 0;
  kos_min float := 0;
BEGIN
  FOR item IN SELECT * FROM jsonb_array_elements(COALESCE(NEW.items, '[]'::jsonb)) LOOP
    SELECT harga_jual INTO harga_sebenar FROM stok WHERE id = item->>'stokId';
    IF harga_sebenar IS NULL THEN
      RAISE EXCEPTION 'Produk % tidak wujud atau telah dipadam', item->>'stokId';
    END IF;
    item_baru := item_baru || jsonb_build_object(
      'stokId', item->>'stokId',
      'nama', item->>'nama',
      'unit', item->>'unit',
      'harga', harga_sebenar,
      'qty', (item->>'qty')::int
    );
    sub := sub + harga_sebenar * (item->>'qty')::int;
  END LOOP;

  NEW.items := item_baru;
  NEW.subjumlah := sub;

  -- Pertahanan asas untuk kos penghantaran: tak boleh kurang daripada kadar
  -- zon termurah. (Kadar EasyParcel sebenar sudah disahkan semasa panggilan
  -- quotation berasingan — ini hanya lapisan pertahanan tambahan di sini.)
  SELECT MIN(kadar_asas) INTO kos_min FROM zon_penghantaran;
  IF NEW.kos_penghantaran IS NULL OR NEW.kos_penghantaran < COALESCE(kos_min, 0) THEN
    NEW.kos_penghantaran := COALESCE(kos_min, 0);
  END IF;

  NEW.jumlah := sub + NEW.kos_penghantaran - COALESCE(NEW.diskaun, 0);
  NEW.status_bayaran := 'menunggu';

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validasi_harga_pesanan_edagang ON pesanan_edagang;
CREATE TRIGGER trg_validasi_harga_pesanan_edagang
  BEFORE INSERT ON pesanan_edagang
  FOR EACH ROW EXECUTE FUNCTION validasi_harga_pesanan_edagang();
