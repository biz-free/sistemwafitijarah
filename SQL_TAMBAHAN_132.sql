-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 132: Deskripsi Produk (SEO) — jadual `stok` sebelum ni
-- HANYA ada nama/kategori/harga/unit, tiada medan penerangan langsung.
-- Kesan SEO sebenar: kemaskiniSEOProduk() (index.html) & produk-preview-gen
-- (edge function) kedua-duanya jana "description" Product schema drpd
-- TEMPLAT generik sama (nama+kategori+harga sahaja) utk SETIAP produk —
-- kandungan hampir serupa merentasi semua halaman produk = "thin/duplicate
-- content" yg menyukarkan Google beza & ranking-kan setiap produk secara
-- individu. Lajur `deskripsi` (pilihan) benarkan pemilik tulis penerangan
-- sebenar per-produk, dipapar di kad produk (index.html) & disuntik ke
-- Product schema + meta description (fallback ke templat lama jika kosong).
-- ═══════════════════════════════════════════════════════════

ALTER TABLE stok ADD COLUMN IF NOT EXISTS deskripsi text;

-- RPC senarai_produk_awam() (index.html, senarai produk kedai online awam) — WAJIB
-- dikemaskini juga sebab senarai lajur pulangan EKSPLISIT (bukan SELECT *), jadi
-- lajur `deskripsi` baharu TIDAK automatik terikut tanpa RPC ni dikemaskini.
-- DROP wajib dahulu — CREATE OR REPLACE gagal bila senarai lajur pulangan berubah.
DROP FUNCTION IF EXISTS public.senarai_produk_awam();
CREATE OR REPLACE FUNCTION public.senarai_produk_awam()
RETURNS TABLE(id text, nama text, unit text, harga_jual double precision, kategori text, deskripsi text, gambar_url text, gambar_urls jsonb, jumlah_terjual bigint, berat double precision)
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT s.id, s.nama, s.unit, s.harga_jual, s.kategori, s.deskripsi, s.gambar_url, s.gambar_urls,
    COALESCE((SELECT SUM((item->>'qty')::int) FROM transaksi t, jsonb_array_elements(t.items) item WHERE item->>'stokId' = s.id), 0)
    + COALESCE((SELECT SUM((item->>'qty')::int) FROM pesanan_edagang o, jsonb_array_elements(o.items) item WHERE item->>'stokId' = s.id AND o.status_bayaran = 'disahkan'), 0)
    AS jumlah_terjual,
    s.berat
  FROM stok s WHERE s.aktif IS NOT FALSE ORDER BY nama;
$function$;
