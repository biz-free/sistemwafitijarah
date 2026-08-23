-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 109: "Pulang Stok" (pekerja pulangkan stok bawaan
-- dalam keadaan BAIK) kini WAJIB pengesahan pemilik dahulu sebelum
-- kredit balik ke stok gudang boleh jual — sama corak dua-fasa
-- seperti "Serah Reject" (SQL_TAMBAHAN_62) yang sedia ada.
--
-- Sebelum ini (SQL_TAMBAHAN_62): pulang_stok_pekerja kredit TERUS ke
-- stok.stok & auto-disahkan (status='disahkan') — pekerja boleh dakwa
-- pulang tanpa pemilik sempat sahkan barang betul2 sampai fizikal.
--
-- Kini: potong stok bawaan pekerja SERTA-MERTA (macam reject) tapi
-- rekod status='menunggu', TIADA kredit ke stok.stok lagi. Pemilik
-- sahkan (baru kredit ke gudang) atau tolak (kuantiti pulang BALIK ke
-- stok bawaan pekerja — sama pattern spt tolak dakwaan reject).
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.pulang_stok_pekerja(p_stok_id text, p_qty int) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_nama text;
BEGIN
  IF p_qty <= 0 THEN RAISE EXCEPTION 'Kuantiti mesti lebih 0'; END IF;
  UPDATE stok_pekerja SET kuantiti = kuantiti - p_qty WHERE pekerja_id = auth.uid() AND stok_id = p_stok_id AND kuantiti >= p_qty;
  IF NOT FOUND THEN RAISE EXCEPTION 'Stok bawaan anda tidak mencukupi'; END IF;
  -- TIADA lagi kredit terus ke stok.stok di sini — tunggu pengesahan pemilik
  -- (putuskan_serahan_produk) supaya barang fizikal disahkan sampai dahulu.
  SELECT nama INTO v_nama FROM stok WHERE id = p_stok_id;
  INSERT INTO serahan_produk (id, pekerja_id, stok_id, stok_nama, kuantiti, jenis, status)
  VALUES (gen_random_uuid()::text, auth.uid(), p_stok_id, COALESCE(v_nama, p_stok_id), p_qty, 'baik', 'menunggu');
END;
$$;
GRANT EXECUTE ON FUNCTION public.pulang_stok_pekerja(text, int) TO authenticated;

-- putuskan_serahan_produk: luaskan skop drpd 'reject' sahaja kepada 'reject' & 'baik'.
-- 'baik' + disahkan = BARU sekarang kredit ke stok gudang (langkah yg dulu berlaku
-- serta-merta). 'reject' + disahkan = tiada perubahan (barang hilang/rosak kekal,
-- tak masuk balik stok jual). Mana-mana jenis + ditolak = kuantiti pulang balik ke
-- stok BAWAAN pekerja (tak berubah drpd tingkah laku reject sedia ada).
CREATE OR REPLACE FUNCTION public.putuskan_serahan_produk(p_id text, p_status text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_row serahan_produk%ROWTYPE;
BEGIN
  IF NOT is_pemilik() THEN RAISE EXCEPTION 'Hanya pemilik boleh putuskan serahan produk'; END IF;
  IF p_status NOT IN ('disahkan','ditolak') THEN RAISE EXCEPTION 'Status tidak sah'; END IF;

  SELECT * INTO v_row FROM serahan_produk WHERE id = p_id AND jenis IN ('reject','baik') AND status = 'menunggu';
  IF NOT FOUND THEN RAISE EXCEPTION 'Rekod tidak dijumpai atau sudah diputuskan'; END IF;

  IF p_status = 'ditolak' THEN
    INSERT INTO stok_pekerja (pekerja_id, stok_id, kuantiti) VALUES (v_row.pekerja_id, v_row.stok_id, v_row.kuantiti)
      ON CONFLICT (pekerja_id, stok_id) DO UPDATE SET kuantiti = stok_pekerja.kuantiti + v_row.kuantiti;
  ELSIF p_status = 'disahkan' AND v_row.jenis = 'baik' THEN
    UPDATE stok SET stok = stok + v_row.kuantiti WHERE id = v_row.stok_id;
  END IF;

  UPDATE serahan_produk SET status = p_status, disahkan_oleh = auth.uid(), disahkan_pada = now() WHERE id = p_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.putuskan_serahan_produk(text, text) TO authenticated;
