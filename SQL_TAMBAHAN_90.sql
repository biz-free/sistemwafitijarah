-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 90: Audit keselamatan menyeluruh (Supabase security
-- advisors) — jumpa 29 fungsi SECURITY DEFINER masih boleh dipanggil
-- oleh 'anon' (pelawat tanpa log masuk) walaupun kebanyakannya fungsi
-- DALAMAN admin/pekerja. Kebanyakan selamat sebab ada semakan
-- auth.uid()/is_pemilik() dalaman (tak boleh dieksploitasi terus),
-- TAPI papan_jualan_pekerja_hari_ini() didapati BENAR-BENAR BOCOR —
-- ia pulangkan nama SEMUA pekerja + jumlah jualan RM hari ini TANPA
-- sebarang semakan auth langsung, boleh dipanggil terus oleh sesiapa
-- via REST endpoint tanpa token.
--
-- Fungsi yang KEKAL anon (memang untuk storefront/pre-order awam):
-- cari_kedai_ikut_telefon, claim_preorder, is_pemilik, jejak_pesanan_awam,
-- maklumat_kedai_awam, semak_ganjaran_rujukan_saya, semak_status_pesanan,
-- senarai_produk_awam, validasi_baucar, validasi_harga_pesanan_edagang,
-- validasi_harga_pre_order, validasi_rujukan — TIDAK disentuh.
-- ═══════════════════════════════════════════════════════════

REVOKE EXECUTE ON FUNCTION public.papan_jualan_pekerja_hari_ini() FROM anon;
REVOKE EXECUTE ON FUNCTION public.easyparcel_status() FROM anon;
REVOKE EXECUTE ON FUNCTION public.lepas_promosi_pesanan_gagal() FROM anon;
REVOKE EXECUTE ON FUNCTION public.lepaskan_preorder_lapuk() FROM anon;
REVOKE EXECUTE ON FUNCTION public.cipta_baucar_bayaran(uuid, text, text, double precision, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.cipta_baucar_harian(uuid, date, double precision, jsonb) FROM anon;
REVOKE EXECUTE ON FUNCTION public.hantar_permohonan_cuti(text, text, date, date, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.kemaskini_profil_sendiri(text, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.pindah_stok_pekerja(uuid, uuid, text, integer) FROM anon;
REVOKE EXECUTE ON FUNCTION public.pulang_stok_pekerja(text, integer) FROM anon;
REVOKE EXECUTE ON FUNCTION public.putuskan_ambil_stok(text, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.putuskan_serahan_produk(text, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.rekod_bayaran(text, double precision) FROM anon;
REVOKE EXECUTE ON FUNCTION public.restock_produk(text, integer) FROM anon;
REVOKE EXECUTE ON FUNCTION public.sahkan_jualan_konsainan(text, jsonb) FROM anon;
REVOKE EXECUTE ON FUNCTION public.serah_produk_reject(text, text, integer, text, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.tugaskan_preorder(text, uuid) FROM anon;

-- Baiki juga "function_search_path_mutable" (best-practice, elak search_path
-- hijack) pada fungsi yang saya cipta sendiri (SQL_TAMBAHAN_84) tanpa
-- SET search_path — tersilap tertinggal.
CREATE OR REPLACE FUNCTION public.kira_tarikh_matang_bonus(p_tarikh_earn date, p_anchor date)
RETURNS date
LANGUAGE plpgsql IMMUTABLE SET search_path TO 'public' AS $function$
DECLARE v_batas date := p_anchor;
BEGIN
  WHILE v_batas <= p_tarikh_earn LOOP
    v_batas := (v_batas + interval '1 month')::date;
  END LOOP;
  RETURN v_batas;
END;
$function$;
