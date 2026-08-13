-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 99: Penugasan Route Harian — pemilik boleh (1) susun
-- MANUAL urutan kedai dalam sesuatu route (bukan auto nearest-neighbour
-- spt sebelum ini), dan (2) tugaskan route tersebut kepada pekerja
-- tertentu pada tarikh tertentu — pekerja terus nampak arahan proaktif
-- "Kedai 1 → 2 → 3..." di Dashboard tanpa perlu cari sendiri.
--
-- Route & keahlian kedai (route_kedai, kedai.route_id) KEKAL spt sedia
-- ada (dikongsi pemilik+pekerja utk kedai sendiri) — hanya TAMBAH
-- urutan manual + lapisan penugasan harian baharu, KEDUA-DUANYA
-- pemilik sahaja (dispatch/arahan ialah keputusan pemilik).
-- ═══════════════════════════════════════════════════════════

ALTER TABLE public.kedai ADD COLUMN IF NOT EXISTS route_urutan integer;

CREATE TABLE IF NOT EXISTS public.penugasan_route_harian (
  id text PRIMARY KEY,
  route_id uuid NOT NULL REFERENCES public.route_kedai(id) ON DELETE CASCADE,
  pekerja_id uuid NOT NULL REFERENCES auth.users(id),
  tarikh date NOT NULL,
  nota text,
  status text NOT NULL DEFAULT 'aktif' CHECK (status IN ('aktif','dibatalkan')),
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.penugasan_route_harian ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "pemilik urus semua penugasan" ON public.penugasan_route_harian;
DROP POLICY IF EXISTS "pekerja lihat penugasan sendiri" ON public.penugasan_route_harian;
CREATE POLICY "pemilik urus semua penugasan" ON public.penugasan_route_harian FOR ALL USING (is_pemilik()) WITH CHECK (is_pemilik());
CREATE POLICY "pekerja lihat penugasan sendiri" ON public.penugasan_route_harian FOR SELECT USING (pekerja_id = auth.uid());

-- Susun semula urutan manual (pemilik sahaja) — swap dgn kedai sebelah
-- ATAS/BAWAH dlm route yg sama, supaya senang guna butang naik/turun di UI
-- tanpa perlu drag-drop (lebih stabil utk peranti mudah alih).
CREATE OR REPLACE FUNCTION public.tukar_urutan_kedai_route(p_kedai_id text, p_arah text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE v_kedai RECORD; v_jiran RECORD;
BEGIN
  IF NOT is_pemilik() THEN RAISE EXCEPTION 'Hanya pemilik boleh susun urutan route'; END IF;
  IF p_arah NOT IN ('naik','turun') THEN RAISE EXCEPTION 'Arah tidak sah'; END IF;

  SELECT id, route_id, COALESCE(route_urutan, 999999) AS urutan INTO v_kedai FROM kedai WHERE id = p_kedai_id;
  IF NOT FOUND OR v_kedai.route_id IS NULL THEN RAISE EXCEPTION 'Kedai tiada dalam mana-mana route'; END IF;

  IF p_arah = 'naik' THEN
    SELECT id, COALESCE(route_urutan,999999) AS urutan INTO v_jiran FROM kedai
      WHERE route_id = v_kedai.route_id AND id <> p_kedai_id AND COALESCE(route_urutan,999999) < v_kedai.urutan
      ORDER BY COALESCE(route_urutan,999999) DESC LIMIT 1;
  ELSE
    SELECT id, COALESCE(route_urutan,999999) AS urutan INTO v_jiran FROM kedai
      WHERE route_id = v_kedai.route_id AND id <> p_kedai_id AND COALESCE(route_urutan,999999) > v_kedai.urutan
      ORDER BY COALESCE(route_urutan,999999) ASC LIMIT 1;
  END IF;
  IF NOT FOUND THEN RETURN; END IF;

  UPDATE kedai SET route_urutan = v_jiran.urutan WHERE id = v_kedai.id;
  UPDATE kedai SET route_urutan = v_kedai.urutan WHERE id = v_jiran.id;
END;
$function$;

-- NOTA: fungsi ni rupanya SUDAH wujud dgn signature LAMA (p_route_id TEXT, bukan
-- UUID) — CREATE OR REPLACE dgn tandatangan berbeza jenis parameter cipta OVERLOAD
-- BAHARU (bukan ganti), sama bug class spt param baharu di hujung. WAJIB drop dahulu:
DROP FUNCTION IF EXISTS public.tetapkan_route_kedai_sendiri(text, text);

-- Bila kedai BAHARU ditambah ke route (checkbox), letak di HUJUNG senarai automatik.
CREATE OR REPLACE FUNCTION public.tetapkan_route_kedai_sendiri(p_kedai_id text, p_route_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE v_max integer;
BEGIN
  IF NOT is_pemilik() AND NOT EXISTS (SELECT 1 FROM kedai WHERE id = p_kedai_id AND didaftarkan_oleh = auth.uid()) THEN
    RAISE EXCEPTION 'Hanya boleh urus route utk kedai yang anda daftarkan sendiri';
  END IF;
  IF p_route_id IS NOT NULL THEN
    SELECT COALESCE(MAX(route_urutan), 0) INTO v_max FROM kedai WHERE route_id = p_route_id;
    UPDATE kedai SET route_id = p_route_id, route_urutan = v_max + 1 WHERE id = p_kedai_id;
  ELSE
    UPDATE kedai SET route_id = NULL, route_urutan = NULL WHERE id = p_kedai_id;
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.cipta_penugasan_harian(p_id text, p_route_id uuid, p_pekerja_id uuid, p_tarikh date, p_nota text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
BEGIN
  IF NOT is_pemilik() THEN RAISE EXCEPTION 'Hanya pemilik boleh tugaskan route'; END IF;
  INSERT INTO penugasan_route_harian (id, route_id, pekerja_id, tarikh, nota, created_by)
  VALUES (p_id, p_route_id, p_pekerja_id, p_tarikh, p_nota, auth.uid());
END;
$function$;

CREATE OR REPLACE FUNCTION public.padam_penugasan_harian(p_id text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
BEGIN
  IF NOT is_pemilik() THEN RAISE EXCEPTION 'Hanya pemilik boleh padam penugasan'; END IF;
  UPDATE penugasan_route_harian SET status = 'dibatalkan' WHERE id = p_id;
END;
$function$;

-- Isi urutan kedai sedia ada yg belum ada nombor (route lama sblm ciri ni wujud) —
-- guna urutan nama supaya konsisten & boleh disusun semula manual selepas ini.
WITH bernombor AS (
  SELECT id, ROW_NUMBER() OVER (PARTITION BY route_id ORDER BY nama) AS n
  FROM kedai WHERE route_id IS NOT NULL AND route_urutan IS NULL
)
UPDATE kedai k SET route_urutan = b.n FROM bernombor b WHERE k.id = b.id;
