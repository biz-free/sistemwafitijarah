-- SQL_TAMBAHAN_47: Maklum & Semak Ganjaran Rujukan
--
-- Pembetulan gap: pembeli yang bayar guna Billplz (kemungkinan majoriti)
-- LANGSUNG tak nampak kod rujukan mereka selepas checkout (halaman
-- pengesahan Billplz menimpa mesej "Kongsi & Dapat Ganjaran"). Tambah
-- pelanggan_telefon pada semak_status_pesanan() supaya index.html boleh
-- papar kod rujukan (= no. telefon pembeli) selepas bayaran Billplz disahkan.
--
-- Juga tambah RPC baharu supaya PERUJUK boleh semak sendiri ganjaran yang
-- pernah dijana untuk mereka (guna no. telefon) — berguna jika emel
-- pemberitahuan tak sampai/hilang.

DROP FUNCTION IF EXISTS semak_status_pesanan(text);

CREATE OR REPLACE FUNCTION public.semak_status_pesanan(p_id text)
RETURNS TABLE(status_bayaran text, status_pesanan text, jumlah double precision, pelanggan_telefon text)
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT status_bayaran, status_pesanan, jumlah, pelanggan_telefon FROM pesanan_edagang WHERE id = p_id
  UNION ALL
  SELECT status_bayaran, status, jumlah_selepas_diskaun, NULL::text FROM pre_order WHERE id = p_id
  LIMIT 1;
$function$;

CREATE OR REPLACE FUNCTION semak_ganjaran_rujukan_saya(p_telefon text)
RETURNS TABLE(kod_ganjaran text, nilai_ganjaran float, created_at timestamptz, tarikh_luput date, sudah_guna boolean, masih_aktif boolean)
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT rg.kod_ganjaran, rg.nilai_ganjaran, rg.created_at, b.tarikh_luput,
         COALESCE(b.bilangan_guna, 0) > 0 AS sudah_guna,
         COALESCE(b.aktif, false) AS masih_aktif
  FROM rujukan_ganjaran rg
  LEFT JOIN baucar b ON b.kod = rg.kod_ganjaran
  WHERE regexp_replace(rg.telefon_perujuk, '[^0-9]', '', 'g') = regexp_replace(trim(p_telefon), '[^0-9]', '', 'g')
  ORDER BY rg.created_at DESC;
$$;
