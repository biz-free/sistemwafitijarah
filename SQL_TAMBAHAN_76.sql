-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 76: Pemilik boleh kemaskini kuantiti permohonan
-- "Ambil Stok" (jenis='ambil') SEBELUM sahkan — kadang kuantiti
-- perlu ditambah/dikurangkan drpd apa yang pekerja mohon asal
-- (cth: stok gudang tak cukup, atau pekerja perlu lebih).
--
-- HANYA boleh kemaskini rekod yang MASIH 'menunggu' (belum
-- diputuskan) — elak pemilik ubah kuantiti rekod yang dah
-- disahkan/ditolak (yang mana stok dah pun bergerak). Selepas
-- kuantiti dikemaskini, alur sahkan sedia ada (putuskan_ambil_stok)
-- baca kuantiti TERKINI drpd jadual terus — tiada perubahan
-- diperlukan pada fungsi tu.
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.kemaskini_kuantiti_ambil_stok(p_id text, p_kuantiti integer)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_pemilik() THEN
    RAISE EXCEPTION 'Hanya pemilik boleh kemaskini kuantiti permohonan';
  END IF;
  IF p_kuantiti <= 0 THEN RAISE EXCEPTION 'Kuantiti mesti lebih 0'; END IF;

  UPDATE serahan_produk SET kuantiti = p_kuantiti
    WHERE id = p_id AND jenis = 'ambil' AND status = 'menunggu';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Permohonan tidak dijumpai atau sudah diputuskan';
  END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.kemaskini_kuantiti_ambil_stok(text, integer) TO authenticated;
