-- ═══════════════════════════════════════════════════════════
--  WAFI TIJARAH TRADING — SQL TAMBAHAN #6
--  Jalankan SEKALI sahaja dalam Supabase SQL Editor.
--  (Baiki: Mohon Cuti gagal "row violates RLS", Claim Pre-Order salah)
-- ═══════════════════════════════════════════════════════════

-- Hantar permohonan cuti secara terus guna auth.uid() di server
-- (elak isu RLS/mismatch id di client sepenuhnya)
CREATE OR REPLACE FUNCTION hantar_permohonan_cuti(
  p_id text, p_jenis text, p_mula date, p_tamat date, p_nota text
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid()) THEN
    RAISE EXCEPTION 'Tidak dibenarkan';
  END IF;
  INSERT INTO permohonan_cuti (id, pekerja_id, jenis, tarikh_mula, tarikh_tamat, nota, status)
  VALUES (p_id, auth.uid(), p_jenis, p_mula, p_tamat, p_nota, 'menunggu');
END;
$$;
GRANT EXECUTE ON FUNCTION hantar_permohonan_cuti(text,text,date,date,text) TO authenticated;

-- Ambil tugasan pre-order secara atomik (elak isu penapis .is()+.select() di client)
CREATE OR REPLACE FUNCTION claim_preorder(p_id text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid()) THEN
    RAISE EXCEPTION 'Tidak dibenarkan';
  END IF;
  UPDATE pre_order SET assigned_pekerja_id = auth.uid()
    WHERE id = p_id AND assigned_pekerja_id IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pre-order ini sudah diambil oleh pekerja lain (atau tidak wujud)';
  END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION claim_preorder(text) TO authenticated;
