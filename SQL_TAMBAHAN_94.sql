-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 94: Tetapan "Diskaun Bayaran Hutang Penuh" per-kedai —
-- sesetengah kedai (cth Mutiara Sg Layar) dapat diskaun tetap (cth 10%)
-- bila mereka BAYAR PENUH hutang sekaligus. rekod_bayaran() sedia ada
-- guna logik DELTA (tolak jumlah literal yg dibayar), jadi bayaran
-- RM848.70 utk hutang RM943 akan tinggalkan baki RM94.30 — SALAH bila
-- baki tu sepatutnya RM0 sebab diskaun. Fungsi baharu rekod_bayaran_penuh()
-- clear hutang terus ke RM0 (settlement penuh), diguna pakai bila pekerja/
-- pemilik tandakan checkbox "Bayaran PENUH dgn diskaun" di UI.
--
-- Turut betulkan rekod SEJARAH Mutiara Sg Layar (kedai_id K4553371):
-- pemilik sahkan kedai ni dah bayar RM848.70 (= RM943 × 90%) sbg
-- settlement PENUH, tapi rekod_bayaran() lama tak pernah dipanggil utk
-- ni jadi kedai.hutang masih tunjuk RM943 & transaksi masih 'hutang'.
-- ═══════════════════════════════════════════════════════════

ALTER TABLE public.kedai
  ADD COLUMN IF NOT EXISTS diskaun_hutang_peratus numeric NOT NULL DEFAULT 0
    CHECK (diskaun_hutang_peratus >= 0 AND diskaun_hutang_peratus <= 100);

ALTER TABLE public.permohonan_bayaran_hutang
  ADD COLUMN IF NOT EXISTS settlement_penuh boolean NOT NULL DEFAULT false;

-- Settlement PENUH — clear hutang kedai terus ke RM0 & tandakan SEMUA
-- transaksi 'hutang' kedai tsb sbg 'selesai', tanpa kira jumlah literal
-- yg dibayar (sebab kurang drpd jumlah asal ATAS SEBAB diskaun yg sah).
CREATE OR REPLACE FUNCTION public.rekod_bayaran_penuh(p_kedai_id text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
BEGIN
  IF NOT is_pemilik() THEN RAISE EXCEPTION 'Hanya pemilik boleh rekod bayaran'; END IF;
  UPDATE kedai SET hutang = 0 WHERE id = p_kedai_id;
  UPDATE transaksi SET status = 'selesai' WHERE kedai_id = p_kedai_id AND status = 'hutang';
END;
$function$;

-- NOTA: cubaan awal anggap CREATE OR REPLACE + parameter baharu berdefault
-- di HUJUNG selamat tanpa DROP — RUPANYA TIDAK. PostgREST/Postgres tetap
-- cipta OVERLOAD BAHARU (6-arg lama + 7-arg baharu wujud serentak), corak
-- bug yg sama spt disebut dlm SQL_TAMBAHAN sebelumnya. DROP signature lama
-- WAJIB dahulu sebelum CREATE OR REPLACE bila menambah parameter — bukan
-- hanya bila menukar/buang parameter.
DROP FUNCTION IF EXISTS public.mohon_bayaran_hutang(text, text, double precision, text, text, text);

CREATE OR REPLACE FUNCTION public.mohon_bayaran_hutang(p_id text, p_kedai_id text, p_jumlah double precision, p_kaedah_bayaran text, p_resit_bukti_url text DEFAULT NULL, p_nota text DEFAULT NULL, p_settlement_penuh boolean DEFAULT false)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Log masuk diperlukan'; END IF;
  IF p_jumlah <= 0 THEN RAISE EXCEPTION 'Jumlah mesti lebih 0'; END IF;
  IF p_kaedah_bayaran NOT IN ('tunai','transfer') THEN RAISE EXCEPTION 'Kaedah bayaran tidak sah'; END IF;

  IF is_pemilik() THEN
    IF p_settlement_penuh THEN
      PERFORM rekod_bayaran_penuh(p_kedai_id);
    ELSE
      PERFORM rekod_bayaran(p_kedai_id, p_jumlah);
    END IF;
    INSERT INTO permohonan_bayaran_hutang (id, kedai_id, pekerja_id, jumlah, kaedah_bayaran, resit_bukti_url, nota, settlement_penuh, status, disahkan_oleh, disahkan_pada)
    VALUES (p_id, p_kedai_id, auth.uid(), p_jumlah, p_kaedah_bayaran, p_resit_bukti_url, p_nota, p_settlement_penuh, 'disahkan', auth.uid(), now());
  ELSE
    INSERT INTO permohonan_bayaran_hutang (id, kedai_id, pekerja_id, jumlah, kaedah_bayaran, resit_bukti_url, nota, settlement_penuh)
    VALUES (p_id, p_kedai_id, auth.uid(), p_jumlah, p_kaedah_bayaran, p_resit_bukti_url, p_nota, p_settlement_penuh);
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.putuskan_bayaran_hutang(p_id text, p_status text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE v_row permohonan_bayaran_hutang%ROWTYPE;
BEGIN
  IF NOT is_pemilik() THEN RAISE EXCEPTION 'Hanya pemilik boleh putuskan permohonan bayaran'; END IF;
  IF p_status NOT IN ('disahkan','ditolak') THEN RAISE EXCEPTION 'Status tidak sah'; END IF;

  SELECT * INTO v_row FROM permohonan_bayaran_hutang WHERE id = p_id AND status = 'menunggu';
  IF NOT FOUND THEN RAISE EXCEPTION 'Permohonan tidak dijumpai atau sudah diputuskan'; END IF;

  IF p_status = 'disahkan' THEN
    IF v_row.settlement_penuh THEN
      PERFORM rekod_bayaran_penuh(v_row.kedai_id);
    ELSE
      PERFORM rekod_bayaran(v_row.kedai_id, v_row.jumlah);
    END IF;
  END IF;

  UPDATE permohonan_bayaran_hutang SET status = p_status, disahkan_oleh = auth.uid(), disahkan_pada = now() WHERE id = p_id;
END;
$function$;

-- ── Pembetulan rekod sejarah: Mutiara Sg Layar (K4553371) ──
-- Kedai ni layak diskaun 10% bila bayar penuh (tetapan baharu di atas).
UPDATE public.kedai SET diskaun_hutang_peratus = 10 WHERE id = 'K4553371';

-- Settlement sebenar: hutang RM943 dijelaskan RM848.70 (90%), clear ke RM0.
UPDATE public.kedai SET hutang = 0 WHERE id = 'K4553371';
UPDATE public.transaksi SET status = 'selesai' WHERE kedai_id = 'K4553371' AND status = 'hutang';

-- Rekod audit permohonan (retroaktif, terus disahkan) supaya sejarah
-- bayaran kekal jelas siapa/bila/berapa sebenar dibayar.
INSERT INTO public.permohonan_bayaran_hutang
  (id, kedai_id, pekerja_id, jumlah, kaedah_bayaran, nota, settlement_penuh, status, disahkan_oleh, disahkan_pada)
VALUES
  ('PBH-KOREKSI-K4553371', 'K4553371', '7c2af1ae-3808-4e9d-a878-c22c2717e90d', 848.70, 'tunai',
   'Pembetulan rekod: bayaran penuh dgn diskaun 10% (RM943 → RM848.70)', true, 'disahkan',
   '7c2af1ae-3808-4e9d-a878-c22c2717e90d', now());
