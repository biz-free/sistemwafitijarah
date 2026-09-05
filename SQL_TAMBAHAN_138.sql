-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 138: Padam Resit Pelupusan/Tukar Expired — pulih stok bawaan pekerja
--
-- Sebelum ni TIADA cara langsung utk padam resit pelupusan/tukar-expired yang
-- tersalah rekod — pemilik terpaksa betulkan manual di database. Fungsi baharu ni
-- padam SEMUA baris pelupusan_stok yg kongsi 1 no. resit (1 hantaran borang boleh
-- byk baris — beberapa produk expired + beberapa produk gantian), dan PULIHKAN
-- balik stok bawaan pekerja bagi baris yg ASALNYA menolak stok bawaan:
--   • Pelupusan biasa (jenis NULL/rosak/expired/hilang/lain) — barang ni ASALNYA
--     drpd bag pekerja (lupus_stok_pekerja tolak terus) → PULIHKAN balik.
--   • Gantian diberi (jenis='tukar_beri') — barang gantian ASALNYA drpd bag
--     pekerja (tukar_stok_expired_kedai tolak terus) → PULIHKAN balik.
--   • Ambil balik expired (jenis='tukar_ambil') — barang ni ASALNYA drpd KEDAI,
--     BUKAN bag pekerja (lihat nota submitTukarExpired: "TIADA potong stok bawaan
--     pekerja") → TIADA apa perlu dipulihkan (baris ni tak pernah ubah stok bawaan).
--
-- Diuji live (BEGIN/ROLLBACK) guna resit sebenar R-260802-237 (Aremier, JHF Food
-- Mart) — pulihkan tepat 3 unit (gantian, S2681163) ke stok bawaan, 17 unit (ambil
-- balik) betul TIDAK disentuh. Baseline 8 → 11 selepas simulasi padam.
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.padam_resit_pelupusan(p_resit text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  r RECORD; v_bil int := 0; v_dipulihkan jsonb := '[]'::jsonb;
BEGIN
  IF NOT is_pemilik() THEN RAISE EXCEPTION 'Hanya pemilik boleh padam resit pelupusan'; END IF;
  IF p_resit IS NULL OR p_resit = '' THEN RAISE EXCEPTION 'No. resit diperlukan'; END IF;

  FOR r IN SELECT * FROM pelupusan_stok WHERE resit = p_resit LOOP
    v_bil := v_bil + 1;
    IF r.jenis IS DISTINCT FROM 'tukar_ambil' THEN
      INSERT INTO stok_pekerja (pekerja_id, stok_id, kuantiti) VALUES (r.pekerja_id, r.stok_id, r.kuantiti)
        ON CONFLICT (pekerja_id, stok_id) DO UPDATE SET kuantiti = stok_pekerja.kuantiti + r.kuantiti;
      v_dipulihkan := v_dipulihkan || jsonb_build_object('stok_id', r.stok_id, 'kuantiti', r.kuantiti);
    END IF;
  END LOOP;

  IF v_bil = 0 THEN RAISE EXCEPTION 'Resit tidak dijumpai'; END IF;

  DELETE FROM pelupusan_stok WHERE resit = p_resit;
  RETURN jsonb_build_object('bilangan_baris', v_bil, 'stok_dipulihkan', v_dipulihkan);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.padam_resit_pelupusan(text) TO authenticated;
