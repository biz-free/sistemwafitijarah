-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 113: Terima Bayaran Hutang turut sokong Belian Peribadi
-- (bukan kedai sahaja) — SATU senarai/dropdown yang sama, cuma tajuk
-- ditukar "Kedai" -> "Kedai & Peribadi".
--
-- Belian peribadi (transaksi.kedai_id IS NULL, guna nama_pembeli sahaja —
-- tiada rekod "kedai" berasingan, jadi tiada medan agregat hutang spt
-- kedai.hutang). Sasaran identiti SATU-SATUNYA yg ada ialah nama_pembeli
-- (teks bebas) — sekumpul transaksi hutang dgn nama_pembeli SAMA dianggap
-- 1 "akaun" utk tujuan bayaran ni, sama pattern spt kumpulan kedai_id.
-- ═══════════════════════════════════════════════════════════

ALTER TABLE permohonan_bayaran_hutang ALTER COLUMN kedai_id DROP NOT NULL;
ALTER TABLE permohonan_bayaran_hutang ADD COLUMN nama_pembeli text;
ALTER TABLE permohonan_bayaran_hutang ADD CONSTRAINT permohonan_bayaran_hutang_satu_sasaran
  CHECK ((kedai_id IS NOT NULL) <> (nama_pembeli IS NOT NULL));

-- ── Sama pattern spt rekod_bayaran/rekod_bayaran_penuh (kedai), utk peribadi ──
CREATE OR REPLACE FUNCTION public.rekod_bayaran_peribadi(p_nama_pembeli text, p_jumlah double precision)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE baki float := p_jumlah; t RECORD;
BEGIN
  IF NOT is_pemilik() THEN RAISE EXCEPTION 'Hanya pemilik boleh rekod bayaran'; END IF;
  FOR t IN
    SELECT id, jumlah FROM transaksi
    WHERE kedai_id IS NULL AND nama_pembeli = p_nama_pembeli AND status = 'hutang'
    ORDER BY tarikh_masa ASC
  LOOP
    EXIT WHEN baki < t.jumlah;
    UPDATE transaksi SET status = 'selesai' WHERE id = t.id;
    baki := baki - t.jumlah;
  END LOOP;
END; $$;

CREATE OR REPLACE FUNCTION public.rekod_bayaran_penuh_peribadi(p_nama_pembeli text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_pemilik() THEN RAISE EXCEPTION 'Hanya pemilik boleh rekod bayaran'; END IF;
  UPDATE transaksi SET status = 'selesai' WHERE kedai_id IS NULL AND nama_pembeli = p_nama_pembeli AND status = 'hutang';
END; $$;

-- ── mohon_bayaran_hutang: tambah p_nama_pembeli. NOTA: menambah parameter
-- baharu (walaupun trailing+default) mencipta OVERLOAD baharu ikut bilangan
-- argumen, BUKAN ganti fungsi lama — mesti DROP signature 7-argumen lama
-- dahulu, jika tidak akan ada 2 fungsi serupa (CREATE OR REPLACE tak cukup). ──
DROP FUNCTION IF EXISTS public.mohon_bayaran_hutang(text, text, double precision, text, text, text, boolean);
CREATE OR REPLACE FUNCTION public.mohon_bayaran_hutang(
  p_id text, p_kedai_id text, p_jumlah double precision, p_kaedah_bayaran text,
  p_resit_bukti_url text DEFAULT NULL, p_nota text DEFAULT NULL, p_settlement_penuh boolean DEFAULT false,
  p_nama_pembeli text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public' AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Log masuk diperlukan'; END IF;
  IF p_jumlah <= 0 THEN RAISE EXCEPTION 'Jumlah mesti lebih 0'; END IF;
  IF p_kaedah_bayaran NOT IN ('tunai','transfer') THEN RAISE EXCEPTION 'Kaedah bayaran tidak sah'; END IF;
  IF (p_kedai_id IS NOT NULL) = (p_nama_pembeli IS NOT NULL) THEN
    RAISE EXCEPTION 'Perlu tepat satu: kedai ATAU nama pembeli peribadi';
  END IF;

  IF is_pemilik() THEN
    IF p_kedai_id IS NOT NULL THEN
      IF p_settlement_penuh THEN
        PERFORM rekod_bayaran_penuh(p_kedai_id);
      ELSE
        PERFORM rekod_bayaran(p_kedai_id, p_jumlah);
      END IF;
    ELSE
      IF p_settlement_penuh THEN
        PERFORM rekod_bayaran_penuh_peribadi(p_nama_pembeli);
      ELSE
        PERFORM rekod_bayaran_peribadi(p_nama_pembeli, p_jumlah);
      END IF;
    END IF;
    INSERT INTO permohonan_bayaran_hutang (id, kedai_id, nama_pembeli, pekerja_id, jumlah, kaedah_bayaran, resit_bukti_url, nota, settlement_penuh, status, disahkan_oleh, disahkan_pada)
    VALUES (p_id, p_kedai_id, p_nama_pembeli, auth.uid(), p_jumlah, p_kaedah_bayaran, p_resit_bukti_url, p_nota, p_settlement_penuh, 'disahkan', auth.uid(), now());
  ELSE
    INSERT INTO permohonan_bayaran_hutang (id, kedai_id, nama_pembeli, pekerja_id, jumlah, kaedah_bayaran, resit_bukti_url, nota, settlement_penuh)
    VALUES (p_id, p_kedai_id, p_nama_pembeli, auth.uid(), p_jumlah, p_kaedah_bayaran, p_resit_bukti_url, p_nota, p_settlement_penuh);
  END IF;
END;
$$;

-- ── putuskan_bayaran_hutang: cawang ikut kedai_id NULL utk laluan peribadi ──
CREATE OR REPLACE FUNCTION public.putuskan_bayaran_hutang(p_id text, p_status text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public' AS $$
DECLARE v_row permohonan_bayaran_hutang%ROWTYPE;
BEGIN
  IF NOT is_pemilik() THEN RAISE EXCEPTION 'Hanya pemilik boleh putuskan permohonan bayaran'; END IF;
  IF p_status NOT IN ('disahkan','ditolak') THEN RAISE EXCEPTION 'Status tidak sah'; END IF;

  SELECT * INTO v_row FROM permohonan_bayaran_hutang WHERE id = p_id AND status = 'menunggu';
  IF NOT FOUND THEN RAISE EXCEPTION 'Permohonan tidak dijumpai atau sudah diputuskan'; END IF;

  IF p_status = 'disahkan' THEN
    IF v_row.kedai_id IS NOT NULL THEN
      IF v_row.settlement_penuh THEN
        PERFORM rekod_bayaran_penuh(v_row.kedai_id);
      ELSE
        PERFORM rekod_bayaran(v_row.kedai_id, v_row.jumlah);
      END IF;
    ELSE
      IF v_row.settlement_penuh THEN
        PERFORM rekod_bayaran_penuh_peribadi(v_row.nama_pembeli);
      ELSE
        PERFORM rekod_bayaran_peribadi(v_row.nama_pembeli, v_row.jumlah);
      END IF;
    END IF;
  END IF;

  UPDATE permohonan_bayaran_hutang SET status = p_status, disahkan_oleh = auth.uid(), disahkan_pada = now() WHERE id = p_id;
END;
$$;
