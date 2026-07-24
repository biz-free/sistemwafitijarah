-- SQL_TAMBAHAN_48: Showcase "Produk Paling Laris" di storefront + pembetulan
-- pengiraan jumlah_terjual.
--
-- BUG DIBETULKAN: senarai_produk_awam() (RPC awam untuk index.html/pesan.html)
-- sebelum ini HANYA kira jualan dari jadual `transaksi` (penghantaran
-- consignment/kedai runcit) — terus abaikan jualan e-dagang online sebenar
-- (`pesanan_edagang`, status_bayaran='disahkan'). Ini menyebabkan sort
-- "🔥 Paling Laris" & showcase produk laris di storefront tak mencerminkan
-- produk yang benar-benar laku dijual online. Kini kira KEDUA-DUA saluran.

CREATE OR REPLACE FUNCTION public.senarai_produk_awam()
RETURNS TABLE(id text, nama text, unit text, harga_jual double precision, kategori text, gambar_url text, gambar_urls jsonb, jumlah_terjual bigint, berat double precision)
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT s.id, s.nama, s.unit, s.harga_jual, s.kategori, s.gambar_url, s.gambar_urls,
    COALESCE((SELECT SUM((item->>'qty')::int) FROM transaksi t, jsonb_array_elements(t.items) item WHERE item->>'stokId' = s.id), 0)
    + COALESCE((SELECT SUM((item->>'qty')::int) FROM pesanan_edagang o, jsonb_array_elements(o.items) item WHERE item->>'stokId' = s.id AND o.status_bayaran = 'disahkan'), 0)
    AS jumlah_terjual,
    s.berat
  FROM stok s ORDER BY nama;
$function$;
