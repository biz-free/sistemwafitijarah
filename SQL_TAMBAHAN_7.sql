-- ═══════════════════════════════════════════════════════════
--  WAFI TIJARAH TRADING — SQL TAMBAHAN #7
--  Jalankan SEKALI sahaja dalam Supabase SQL Editor.
--  (Tempoh tugasan, delete data, gambar berbilang, consignment,
--   tugaskan pekerja, dashboard notifikasi/status live)
-- ═══════════════════════════════════════════════════════════

-- ═══ Pre-Order: tempoh tugasan (auto-lepas jika lepas 1 hari) ═══
ALTER TABLE pre_order ADD COLUMN IF NOT EXISTS claimed_at timestamptz;

-- Lepaskan (unclaim) tugasan yang diambil tapi tak selesai melepasi hari yang sama
-- — dipanggil setiap kali senarai pre-order dimuat, supaya automatik pulang ke kumpulan.
CREATE OR REPLACE FUNCTION lepaskan_preorder_lapuk() RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE pre_order SET assigned_pekerja_id = NULL, claimed_at = NULL
  WHERE assigned_pekerja_id IS NOT NULL
    AND status != 'selesai'
    AND claimed_at::date < CURRENT_DATE;
END;
$$;
GRANT EXECUTE ON FUNCTION lepaskan_preorder_lapuk() TO authenticated, anon;

-- Kemaskini claim_preorder supaya rekod claimed_at sekali
CREATE OR REPLACE FUNCTION claim_preorder(p_id text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid()) THEN
    RAISE EXCEPTION 'Tidak dibenarkan';
  END IF;
  UPDATE pre_order SET assigned_pekerja_id = auth.uid(), claimed_at = now()
    WHERE id = p_id AND assigned_pekerja_id IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pre-order ini sudah diambil oleh pekerja lain (atau tidak wujud)';
  END IF;
END;
$$;

-- Pemilik boleh tugaskan/ubah tugasan pekerja terus (bukan sekadar pekerja claim sendiri)
CREATE OR REPLACE FUNCTION tugaskan_preorder(p_id text, p_pekerja_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'pemilik') THEN
    RAISE EXCEPTION 'Hanya pemilik boleh tugaskan pekerja';
  END IF;
  UPDATE pre_order SET assigned_pekerja_id = p_pekerja_id, claimed_at = CASE WHEN p_pekerja_id IS NULL THEN NULL ELSE now() END
  WHERE id = p_id;
END;
$$;
GRANT EXECUTE ON FUNCTION tugaskan_preorder(text, uuid) TO authenticated;

-- ═══ Consignment (kedai letak barang dulu, bayar lepas jual) — nilai bayar_metod baharu ═══
-- (medan bayar_metod dah wujud sebagai text bebas, tiada perubahan skema diperlukan;
--  'consignment' cuma satu lagi nilai yang sah, dikawal di sisi aplikasi)

-- ═══ Gambar produk berbilang (galeri) ═══
ALTER TABLE stok ADD COLUMN IF NOT EXISTS gambar_urls jsonb DEFAULT '[]';

DROP FUNCTION IF EXISTS senarai_produk_awam();
CREATE FUNCTION senarai_produk_awam()
RETURNS TABLE(id text, nama text, unit text, harga_jual float, kategori text, gambar_url text, gambar_urls jsonb, jumlah_terjual bigint)
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT s.id, s.nama, s.unit, s.harga_jual, s.kategori, s.gambar_url, s.gambar_urls,
    COALESCE((SELECT SUM((item->>'qty')::int) FROM transaksi t, jsonb_array_elements(t.items) item WHERE item->>'stokId' = s.id), 0) AS jumlah_terjual
  FROM stok s ORDER BY nama;
$$;
GRANT EXECUTE ON FUNCTION senarai_produk_awam() TO anon, authenticated;

-- ═══ Padam data (pemilik sahaja) ═══
DROP POLICY IF EXISTS "pemilik padam stok" ON stok;
CREATE POLICY "pemilik padam stok" ON stok FOR DELETE USING (is_pemilik());
DROP POLICY IF EXISTS "pemilik padam kedai" ON kedai;
CREATE POLICY "pemilik padam kedai" ON kedai FOR DELETE USING (is_pemilik());
DROP POLICY IF EXISTS "pemilik padam transaksi" ON transaksi;
CREATE POLICY "pemilik padam transaksi" ON transaksi FOR DELETE USING (is_pemilik());
DROP POLICY IF EXISTS "pemilik padam pre_order" ON pre_order;
CREATE POLICY "pemilik padam pre_order" ON pre_order FOR DELETE USING (is_pemilik());
DROP POLICY IF EXISTS "pemilik padam kehadiran" ON kehadiran;
CREATE POLICY "pemilik padam kehadiran" ON kehadiran FOR DELETE USING (is_pemilik());
DROP POLICY IF EXISTS "pemilik padam permohonan_cuti" ON permohonan_cuti;
CREATE POLICY "pemilik padam permohonan_cuti" ON permohonan_cuti FOR DELETE USING (is_pemilik());
DROP POLICY IF EXISTS "pemilik padam stok_pekerja" ON stok_pekerja;
CREATE POLICY "pemilik padam stok_pekerja" ON stok_pekerja FOR DELETE USING (is_pemilik());

-- ═══ Notifikasi ringkas — kiraan siap (tiada jadual baharu, kira terus dari data sedia ada) ═══
-- Pemilik: bilangan permohonan cuti "menunggu" + pre-order "baru"
-- Pekerja: bilangan pre-order "baru" yang belum ditugaskan
-- (Dikira terus di client bila diperlukan — tiada perubahan skema untuk ini)
