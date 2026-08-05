-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 87: senarai_produk_awam() (dipanggil oleh index.html DAN
-- pesan.html — storefront B2C & borang B2B repeat-order) langsung TAK
-- tapis produk tidak aktif (lajur stok.aktif, SQL_TAMBAHAN_72) — pelanggan
-- awam masih nampak & boleh order produk yang dah "dipadam"/nyahaktifkan
-- oleh pemilik dalam pengurusan.html.
--
-- NOTA PENTING: CREATE OR REPLACE pada fungsi ini automatik tercetus
-- trigger auto-revoke-anon-execute projek (SQL_TAMBAHAN_67), MENANGGALKAN
-- akses anon/PUBLIC yang MEMANG DIPERLUKAN sebab fungsi ni dipanggil oleh
-- pelawat storefront TANPA log masuk. Kena GRANT semula secara eksplicit
-- selepas replace — beza drpd RPC dalaman (pengurusan.html) yang memang
-- patut anon-restricted. Disahkan selepas fix: PUBLIC/anon/authenticated
-- semua wujud, sama macam RPC "_awam" lain (maklumat_kedai_awam dll).
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.senarai_produk_awam()
RETURNS TABLE(id text, nama text, unit text, harga_jual double precision, kategori text, gambar_url text, gambar_urls jsonb, jumlah_terjual bigint, berat double precision)
LANGUAGE sql SECURITY DEFINER SET search_path TO 'public' AS $function$
  SELECT s.id, s.nama, s.unit, s.harga_jual, s.kategori, s.gambar_url, s.gambar_urls,
    COALESCE((SELECT SUM((item->>'qty')::int) FROM transaksi t, jsonb_array_elements(t.items) item WHERE item->>'stokId' = s.id), 0)
    + COALESCE((SELECT SUM((item->>'qty')::int) FROM pesanan_edagang o, jsonb_array_elements(o.items) item WHERE item->>'stokId' = s.id AND o.status_bayaran = 'disahkan'), 0)
    AS jumlah_terjual,
    s.berat
  FROM stok s WHERE s.aktif IS NOT FALSE ORDER BY nama;
$function$;

GRANT EXECUTE ON FUNCTION public.senarai_produk_awam() TO anon, authenticated, PUBLIC;
