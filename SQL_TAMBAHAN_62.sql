-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 62: Serahan produk (pulangan biasa + reject) — jejak
-- audit "produk dipulangkan" dan alur kelulusan produk reject/rosak
-- yang tak boleh dikira balik sebagai stok boleh jual.
-- ═══════════════════════════════════════════════════════════

CREATE TABLE serahan_produk (
  id text PRIMARY KEY,
  pekerja_id uuid REFERENCES auth.users(id) NOT NULL,
  stok_id text REFERENCES stok(id),
  stok_nama text NOT NULL,
  kuantiti integer NOT NULL CHECK (kuantiti > 0),
  jenis text NOT NULL CHECK (jenis IN ('baik','reject')),
  sebab text,
  gambar_url text,
  status text NOT NULL DEFAULT 'menunggu' CHECK (status IN ('menunggu','disahkan','ditolak')),
  disahkan_oleh uuid REFERENCES auth.users(id),
  disahkan_pada timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE serahan_produk ENABLE ROW LEVEL SECURITY;

CREATE POLICY "staff lihat serahan produk" ON serahan_produk FOR SELECT
  USING (pekerja_id = auth.uid() OR is_pemilik());
CREATE POLICY "pemilik urus semua serahan produk" ON serahan_produk FOR ALL
  USING (is_pemilik());

-- Storan: bukti gambar produk reject (persendirian, sama corak spt serahan-cash-resit).
INSERT INTO storage.buckets (id, name, public) VALUES ('serahan-produk-gambar', 'serahan-produk-gambar', false)
  ON CONFLICT (id) DO NOTHING;
CREATE POLICY "staff boleh upload gambar serahan produk" ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'serahan-produk-gambar' AND auth.role() = 'authenticated');
CREATE POLICY "staff boleh lihat gambar serahan produk" ON storage.objects FOR SELECT
  USING (bucket_id = 'serahan-produk-gambar' AND auth.role() = 'authenticated');

-- pulang_stok_pekerja: kekal fungsi sedia ada (pulang ke stok gudang boleh jual),
-- tambah log serahan_produk (jenis='baik', auto-disahkan — tiada kelulusan pemilik
-- diperlukan sebab dah pun kembali ke stok jual sedia) supaya kekal dalam dashboard
-- "Produk Dipulangkan" untuk audit.
CREATE OR REPLACE FUNCTION public.pulang_stok_pekerja(p_stok_id text, p_qty int) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_nama text;
BEGIN
  IF p_qty <= 0 THEN RAISE EXCEPTION 'Kuantiti mesti lebih 0'; END IF;
  UPDATE stok_pekerja SET kuantiti = kuantiti - p_qty WHERE pekerja_id = auth.uid() AND stok_id = p_stok_id AND kuantiti >= p_qty;
  IF NOT FOUND THEN RAISE EXCEPTION 'Stok bawaan anda tidak mencukupi'; END IF;
  UPDATE stok SET stok = stok + p_qty WHERE id = p_stok_id;
  SELECT nama INTO v_nama FROM stok WHERE id = p_stok_id;
  INSERT INTO serahan_produk (id, pekerja_id, stok_id, stok_nama, kuantiti, jenis, status)
  VALUES (gen_random_uuid()::text, auth.uid(), p_stok_id, COALESCE(v_nama, p_stok_id), p_qty, 'baik', 'disahkan');
END;
$$;
GRANT EXECUTE ON FUNCTION public.pulang_stok_pekerja(text, int) TO authenticated;

-- serah_produk_reject: tolak terus dari stok bawaan pekerja (barang dah keluar dari
-- beg dia secara fizikal) TAPI TIDAK ditambah balik ke stok.stok (tak boleh dijual) —
-- rekod status='menunggu' sehingga pemilik semak & sahkan/tolak.
CREATE OR REPLACE FUNCTION public.serah_produk_reject(
  p_id text, p_stok_id text, p_qty int, p_sebab text, p_gambar_url text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_nama text;
BEGIN
  IF p_qty <= 0 THEN RAISE EXCEPTION 'Kuantiti mesti lebih 0'; END IF;
  UPDATE stok_pekerja SET kuantiti = kuantiti - p_qty WHERE pekerja_id = auth.uid() AND stok_id = p_stok_id AND kuantiti >= p_qty;
  IF NOT FOUND THEN RAISE EXCEPTION 'Stok bawaan anda tidak mencukupi'; END IF;
  SELECT nama INTO v_nama FROM stok WHERE id = p_stok_id;
  INSERT INTO serahan_produk (id, pekerja_id, stok_id, stok_nama, kuantiti, jenis, sebab, gambar_url)
  VALUES (p_id, auth.uid(), p_stok_id, COALESCE(v_nama, p_stok_id), p_qty, 'reject', p_sebab, p_gambar_url);
END;
$$;
GRANT EXECUTE ON FUNCTION public.serah_produk_reject(text, text, int, text, text) TO authenticated;

-- putuskan_serahan_produk: pemilik sahkan/tolak dakwaan reject. Jika DITOLAK (pemilik
-- tak setuju dakwaan rosak), kuantiti dipulangkan BALIK ke stok bawaan pekerja (bukan
-- ke stok gudang) supaya pekerja perlu jelaskan/uruskan semula — bukan hilang senyap.
CREATE OR REPLACE FUNCTION public.putuskan_serahan_produk(p_id text, p_status text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_row serahan_produk%ROWTYPE;
BEGIN
  IF NOT is_pemilik() THEN RAISE EXCEPTION 'Hanya pemilik boleh putuskan serahan produk'; END IF;
  IF p_status NOT IN ('disahkan','ditolak') THEN RAISE EXCEPTION 'Status tidak sah'; END IF;

  SELECT * INTO v_row FROM serahan_produk WHERE id = p_id AND jenis = 'reject' AND status = 'menunggu';
  IF NOT FOUND THEN RAISE EXCEPTION 'Rekod tidak dijumpai atau sudah diputuskan'; END IF;

  IF p_status = 'ditolak' THEN
    INSERT INTO stok_pekerja (pekerja_id, stok_id, kuantiti) VALUES (v_row.pekerja_id, v_row.stok_id, v_row.kuantiti)
      ON CONFLICT (pekerja_id, stok_id) DO UPDATE SET kuantiti = stok_pekerja.kuantiti + v_row.kuantiti;
  END IF;

  UPDATE serahan_produk SET status = p_status, disahkan_oleh = auth.uid(), disahkan_pada = now() WHERE id = p_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.putuskan_serahan_produk(text, text) TO authenticated;
