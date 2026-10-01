-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 156: Skim diskaun bayar awal untuk HUTANG >= minima (RM500),
-- bermula 1 Oktober 2026.
--
--   Bayar dalam <= 5 hari dari tarikh invois  -> diskaun 10%
--   Bayar dalam <= 7 hari                     -> diskaun 5%
--   Lebih 7 hari                              -> harga penuh
--
-- Cara kerja (ikut senibina sedia ada SQL 107 — diskaun diberi di awal, dilucuthak
-- automatik oleh cron harian 00:30 MY):
--   * Invois hutang baharu (kaedah 'hutang', jumlah >= minima, tarikh invois >=
--     skim_hutang_mula) direkod dgn 10%, tarikh_akhir_bayaran = tarikh invois + 5.
--   * Cron: lepas tarikh_akhir_bayaran -> 5%; lepas (tarikh_akhir + 2 hari) -> 0%.
--     transaksi.jumlah & kedai.hutang dilaras automatik pada setiap penurunan.
--   * Kadar, bilangan hari & tarikh mula boleh diubah di jadual tetapan.
--   * Tambahan: jualan TUNAI / TRANSFER serta-merta untuk pembelian BAWAH minima dapat
--     diskaun kecil 2% (diskaun_segera_kecil_peratus). Bila >= minima, kadar sedia ada
--     (tunai 5% / transfer 10%, pilihan pekerja) kekal.
--   * Invois SEBELUM tarikh mula dan consignment TIDAK berubah.
--   * Pemilik boleh lanjutkan tarikh_akhir_bayaran (SQL 144) SEBELUM cron menurunkan
--     diskaun; diskaun yg sudah diturunkan tidak dipulihkan secara automatik.
-- Fungsi submit_penghantaran di bawah = SQL 123 + blok skim sahaja.
-- ═══════════════════════════════════════════════════════════

ALTER TABLE public.tetapan ADD COLUMN IF NOT EXISTS skim_hutang_mula date DEFAULT DATE '2026-10-01';
ALTER TABLE public.tetapan ADD COLUMN IF NOT EXISTS skim_hutang_hari_awal integer DEFAULT 5;
ALTER TABLE public.tetapan ADD COLUMN IF NOT EXISTS skim_hutang_peratus_awal double precision DEFAULT 10;
ALTER TABLE public.tetapan ADD COLUMN IF NOT EXISTS skim_hutang_hari_akhir integer DEFAULT 7;
ALTER TABLE public.tetapan ADD COLUMN IF NOT EXISTS skim_hutang_peratus_akhir double precision DEFAULT 5;
-- Diskaun kecil: bayar TUNAI / TRANSFER serta-merta (hari sama) untuk pembelian BAWAH minima.
ALTER TABLE public.tetapan ADD COLUMN IF NOT EXISTS diskaun_segera_kecil_peratus double precision DEFAULT 2;
UPDATE public.tetapan SET
  skim_hutang_mula = COALESCE(skim_hutang_mula, DATE '2026-10-01'),
  skim_hutang_hari_awal = COALESCE(skim_hutang_hari_awal, 5),
  skim_hutang_peratus_awal = COALESCE(skim_hutang_peratus_awal, 10),
  skim_hutang_hari_akhir = COALESCE(skim_hutang_hari_akhir, 7),
  skim_hutang_peratus_akhir = COALESCE(skim_hutang_peratus_akhir, 5),
  diskaun_segera_kecil_peratus = COALESCE(diskaun_segera_kecil_peratus, 2)
WHERE id = 1;

ALTER TABLE public.transaksi ADD COLUMN IF NOT EXISTS skim_hutang_berperingkat boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION public.submit_penghantaran(
  p_id text, p_kedai_id text, p_items jsonb, p_jumlah double precision, p_status text, p_nota text, p_resit text,
  p_jarak_km double precision DEFAULT 0, p_nama_pembeli text DEFAULT NULL::text, p_kaedah_bayaran text DEFAULT 'tunai'::text,
  p_jumlah_asal double precision DEFAULT NULL::double precision, p_diskaun_peratus double precision DEFAULT 0,
  p_resit_bukti_url text DEFAULT NULL::text, p_pekerja_id_override uuid DEFAULT NULL::uuid,
  p_tarikh_masa timestamp with time zone DEFAULT NULL::timestamp with time zone,
  p_tarikh_akhir_bayaran date DEFAULT NULL::date, p_diskaun_pilihan text DEFAULT NULL::text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  item jsonb; v_pekerja_id uuid; v_tarikh_masa timestamptz;
  v_minima double precision; v_kadar_cod double precision; v_kadar_transfer double precision;
  v_sub double precision := 0; v_harga double precision; v_jumlah_final double precision;
  v_diskaun_efektif double precision;
  v_skim_mula date; v_hari_awal int; v_peratus_awal double precision; v_peratus_kecil double precision;
  v_skim boolean := false; v_tarikh_akhir date := p_tarikh_akhir_bayaran;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid()) THEN
    RAISE EXCEPTION 'Tidak dibenarkan';
  END IF;

  v_pekerja_id := CASE WHEN p_pekerja_id_override IS NOT NULL AND is_pemilik() THEN p_pekerja_id_override ELSE auth.uid() END;
  v_tarikh_masa := CASE WHEN p_tarikh_masa IS NOT NULL AND is_pemilik() THEN p_tarikh_masa ELSE now() END;

  SELECT minima_transfer, diskaun_cod_peratus, diskaun_peratus,
         skim_hutang_mula, skim_hutang_hari_awal, skim_hutang_peratus_awal, diskaun_segera_kecil_peratus
    INTO v_minima, v_kadar_cod, v_kadar_transfer,
         v_skim_mula, v_hari_awal, v_peratus_awal, v_peratus_kecil
    FROM tetapan WHERE id = 1;

  -- Kira semula subjumlah SEBENAR drpd harga_jual sebenar di stok — server
  -- tak percaya jumlah dihantar client (sama pola dgn validasi_harga_pesanan_edagang
  -- / validasi_harga_pre_order).
  FOR item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    SELECT harga_jual INTO v_harga FROM stok WHERE id = item->>'stokId';
    IF v_harga IS NULL THEN
      RAISE EXCEPTION 'Produk % tidak wujud atau telah dipadam', item->>'stokId';
    END IF;
    v_sub := v_sub + v_harga * (item->>'qty')::int;
  END LOOP;

  IF COALESCE(v_minima, 0) > 0 AND v_sub >= v_minima
     AND p_kaedah_bayaran = 'hutang'
     AND v_skim_mula IS NOT NULL
     AND (v_tarikh_masa AT TIME ZONE 'Asia/Kuala_Lumpur')::date >= v_skim_mula THEN
    -- Skim bayar awal (SQL 156): hutang >= minima mula dgn diskaun kadar awal,
    -- diturunkan automatik oleh cron lucuthak_diskaun_lewat_bayar() ikut hari.
    -- Pilihan diskaun pekerja diabaikan; tarikh akhir = tarikh invois + hari awal.
    v_skim := true;
    v_diskaun_efektif := COALESCE(v_peratus_awal, 0);
    v_tarikh_akhir := (v_tarikh_masa AT TIME ZONE 'Asia/Kuala_Lumpur')::date + COALESCE(v_hari_awal, 5);
  ELSIF COALESCE(v_minima, 0) > 0 AND v_sub >= v_minima THEN
    IF p_diskaun_pilihan IS NULL OR p_diskaun_pilihan NOT IN ('0', 'cod', 'transfer') THEN
      RAISE EXCEPTION 'Pilihan diskaun wajib (0%% / kadar tunai / kadar transfer) untuk jumlah >= %', v_minima;
    END IF;
    v_diskaun_efektif := CASE p_diskaun_pilihan
      WHEN 'cod' THEN COALESCE(v_kadar_cod, 0)
      WHEN 'transfer' THEN COALESCE(v_kadar_transfer, 0)
      ELSE 0
    END;
  ELSIF p_kaedah_bayaran IN ('tunai', 'transfer') AND p_status = 'selesai'
        AND v_skim_mula IS NOT NULL
        AND (v_tarikh_masa AT TIME ZONE 'Asia/Kuala_Lumpur')::date >= v_skim_mula THEN
    -- Bawah minima: bayar tunai / instant transfer terus (status selesai) dapat diskaun kecil.
    v_diskaun_efektif := COALESCE(v_peratus_kecil, 0);
  ELSE
    v_diskaun_efektif := 0;
  END IF;

  v_jumlah_final := ROUND((v_sub * (1 - v_diskaun_efektif / 100))::numeric, 2);

  IF EXISTS (
    SELECT 1 FROM transaksi
    WHERE created_by = v_pekerja_id::text
      AND kedai_id IS NOT DISTINCT FROM p_kedai_id
      AND items = p_items
      AND jumlah = v_jumlah_final
      AND kaedah_bayaran = p_kaedah_bayaran
      AND tarikh_masa BETWEEN v_tarikh_masa - interval '5 minutes' AND v_tarikh_masa + interval '5 minutes'
  ) THEN
    RAISE EXCEPTION 'Transaksi sama persis (kedai, barang & jumlah sama) baru sahaja direkod dalam 5 minit lepas — kemungkinan tersilap tekan dua kali. Semak Sejarah Penghantaran sebelum cuba lagi.';
  END IF;

  FOR item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    UPDATE stok_pekerja SET kuantiti = kuantiti - (item->>'qty')::int
      WHERE pekerja_id = v_pekerja_id AND stok_id = item->>'stokId' AND kuantiti >= (item->>'qty')::int;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Stok bawaan tidak mencukupi untuk %', item->>'stokId';
    END IF;
  END LOOP;

  INSERT INTO transaksi (id, kedai_id, nama_pembeli, items, jumlah, status, nota, resit, jarak_km, created_by, kaedah_bayaran, jumlah_asal, diskaun_peratus, jualan_disahkan, resit_bukti_url, tarikh_masa, tarikh_akhir_bayaran, skim_hutang_berperingkat)
  VALUES (p_id, p_kedai_id, p_nama_pembeli, p_items, v_jumlah_final, p_status, p_nota, p_resit, p_jarak_km, v_pekerja_id::text, p_kaedah_bayaran, v_sub, v_diskaun_efektif, (p_kaedah_bayaran <> 'consignment'), p_resit_bukti_url, v_tarikh_masa, v_tarikh_akhir, v_skim);

  UPDATE kedai SET
    hutang = hutang + (CASE WHEN p_status = 'hutang' THEN v_jumlah_final ELSE 0 END),
    last_visit = CURRENT_DATE::text,
    route_id = NULL,
    route_urutan = NULL
  WHERE id = p_kedai_id;

  UPDATE baucar_bayaran SET status = 'dibatalkan'
    WHERE pekerja_id = v_pekerja_id AND kategori = 'upah_harian'
      AND tarikh = (v_tarikh_masa AT TIME ZONE 'Asia/Kuala_Lumpur')::date
      AND status IN ('draf','diluluskan');

  IF p_kedai_id IS NOT NULL THEN
    PERFORM sync_bonus_kedai_baru(p_kedai_id);
  END IF;
END;
$function$;


-- Cron harian (jadual 'lucuthak-diskaun-harian' dari SQL 107 sedia ada, tak perlu jadual semula):
-- invois skim diturunkan ikut peringkat; invois lain kekal logik SQL 107.
CREATE OR REPLACE FUNCTION public.lucuthak_diskaun_lewat_bayar()
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
  t RECORD;
  v_selisih double precision;
  v_hari date := (now() AT TIME ZONE 'Asia/Kuala_Lumpur')::date;
  v_hari_awal int; v_hari_akhir int; v_peratus_akhir double precision;
  v_sasaran double precision; v_jumlah_baru double precision;
BEGIN
  SELECT COALESCE(skim_hutang_hari_awal, 5), COALESCE(skim_hutang_hari_akhir, 7), COALESCE(skim_hutang_peratus_akhir, 5)
    INTO v_hari_awal, v_hari_akhir, v_peratus_akhir
    FROM tetapan WHERE id = 1;

  -- 1) Invois LAMA (bukan skim) — kekal SQL 107: satu peringkat, terus 0% selepas tarikh akhir.
  FOR t IN
    SELECT * FROM transaksi
    WHERE status = 'hutang'
      AND kaedah_bayaran <> 'consignment'
      AND NOT skim_hutang_berperingkat
      AND diskaun_peratus > 0
      AND NOT diskaun_dilucuthak
      AND tarikh_akhir_bayaran IS NOT NULL
      AND tarikh_akhir_bayaran < v_hari
  LOOP
    v_selisih := t.jumlah_asal - t.jumlah;
    UPDATE transaksi SET jumlah = jumlah_asal, diskaun_peratus = 0, diskaun_dilucuthak = true WHERE id = t.id;
    IF t.kedai_id IS NOT NULL AND v_selisih > 0 THEN
      UPDATE kedai SET hutang = hutang + v_selisih WHERE id = t.kedai_id;
    END IF;
  END LOOP;

  -- 2) Invois SKIM — turun ikut hari melepasi tarikh_akhir_bayaran (= invois + hari awal).
  FOR t IN
    SELECT * FROM transaksi
    WHERE status = 'hutang'
      AND skim_hutang_berperingkat
      AND diskaun_peratus > 0
      AND tarikh_akhir_bayaran IS NOT NULL
      AND tarikh_akhir_bayaran < v_hari
  LOOP
    IF v_hari > t.tarikh_akhir_bayaran + GREATEST(v_hari_akhir - v_hari_awal, 0) THEN
      v_sasaran := 0;
    ELSE
      v_sasaran := v_peratus_akhir;
    END IF;

    IF v_sasaran < t.diskaun_peratus THEN
      v_jumlah_baru := ROUND((t.jumlah_asal * (1 - v_sasaran / 100))::numeric, 2);
      v_selisih := v_jumlah_baru - t.jumlah;
      UPDATE transaksi SET
        jumlah = v_jumlah_baru,
        diskaun_peratus = v_sasaran,
        diskaun_dilucuthak = (v_sasaran = 0)
      WHERE id = t.id;
      IF t.kedai_id IS NOT NULL AND v_selisih > 0 THEN
        UPDATE kedai SET hutang = hutang + v_selisih WHERE id = t.kedai_id;
      END IF;
    END IF;
  END LOOP;
END;
$function$;
