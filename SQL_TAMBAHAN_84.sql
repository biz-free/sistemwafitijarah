-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 84: Sistem pembayaran Bonus Kedai Baru — DIKUMPUL &
-- DIBAYAR BERASINGAN drpd upah harian, matang ikut kitaran bulanan
-- tetap (30 hari dari tarikh ciri ini bermula), pemilik tick utk bayar
-- (boleh sekalikan dgn baucar harian atau berasingan).
--
-- SEBELUM ini: bonus kedai baru dikira LIVE setiap kali (bonusKedaiEvents())
-- terus dari data transaksi/kedai — TIADA rekod berasingan, & terus
-- dimasukkan ke JUMLAH BOLEH BAYAR baucar harian (kiraUpahPenuhHari()).
-- Keputusan pemilik: bonus MULAI HARI INI dikumpul dalam ledger
-- berasingan, cuma MATANG (layak dibayar) selepas genap kitaran 1 bulan
-- ikut tarikh ciri ini bermula (bukan 30 hari rolling ikut setiap kedai).
-- Bonus yang diperolehi SEBELUM ciri ini (tarikh < bonus_anchor_tarikh)
-- kekal ikut sistem lama (live-computed, sudah termasuk dlm baucar lampau).
--
-- Asas perakaunan Untung Bersih (Laporan/Laporan Harian) KEKAL accrual —
-- kos bonus tetap diiktiraf pada hari ia DIPEROLEHI (tiada perubahan pada
-- bonusKedaiEvents()/kosKedaiBaru client-side), BUKAN pada hari dibayar.
-- ═══════════════════════════════════════════════════════════

-- 1. Anchor tarikh kitaran bulanan (ditetapkan SEKALI, hari ciri ini deploy)
ALTER TABLE public.tetapan ADD COLUMN IF NOT EXISTS bonus_anchor_tarikh date;
UPDATE public.tetapan SET bonus_anchor_tarikh = CURRENT_DATE WHERE id = 1 AND bonus_anchor_tarikh IS NULL;

-- 2. Kategori baucar baharu utk bayaran bonus berasingan (bukan gabung upah_harian)
ALTER TABLE public.baucar_bayaran DROP CONSTRAINT IF EXISTS baucar_bayaran_kategori_check;
ALTER TABLE public.baucar_bayaran ADD CONSTRAINT baucar_bayaran_kategori_check
  CHECK (kategori = ANY (ARRAY['petrol','upah','makan','upah_harian','bonus_kedai']));

-- 3. Ledger bonus kedai baru
CREATE TABLE IF NOT EXISTS public.bonus_kedai_baru (
  id text PRIMARY KEY,
  kedai_id text NOT NULL REFERENCES public.kedai(id),
  pekerja_id uuid NOT NULL REFERENCES auth.users(id),
  label text NOT NULL,
  jumlah double precision NOT NULL CHECK (jumlah > 0),
  tarikh_diperolehi date NOT NULL,
  tarikh_matang date NOT NULL,
  status text NOT NULL DEFAULT 'belum_dibayar' CHECK (status = ANY (ARRAY['belum_dibayar','dibayar'])),
  dibayar_pada timestamptz,
  baucar_id text REFERENCES public.baucar_bayaran(id),
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.bonus_kedai_baru ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "pemilik urus semua bonus kedai" ON public.bonus_kedai_baru;
DROP POLICY IF EXISTS "staff lihat bonus kedai sendiri" ON public.bonus_kedai_baru;
CREATE POLICY "pemilik urus semua bonus kedai" ON public.bonus_kedai_baru FOR ALL USING (is_pemilik());
CREATE POLICY "staff lihat bonus kedai sendiri" ON public.bonus_kedai_baru FOR SELECT USING (pekerja_id = auth.uid() OR is_pemilik());

-- 4. Tarikh matang = titik kitaran-bulanan-tetap PERTAMA (dari anchor) yang > tarikh diperolehi
CREATE OR REPLACE FUNCTION public.kira_tarikh_matang_bonus(p_tarikh_earn date, p_anchor date)
RETURNS date
LANGUAGE plpgsql IMMUTABLE AS $function$
DECLARE v_batas date := p_anchor;
BEGIN
  WHILE v_batas <= p_tarikh_earn LOOP
    v_batas := (v_batas + interval '1 month')::date;
  END LOOP;
  RETURN v_batas;
END;
$function$;

-- 5. Sync bonus utk 1 kedai — replika bonusKedaiEvents() (pengurusan.html) dlm SQL,
--    idempoten (ON id konflik = tiada apa-apa), HANYA rekod event bertarikh >= anchor
--    (event sebelum anchor kekal ikut sistem lama, tak disentuh).
CREATE OR REPLACE FUNCTION public.sync_bonus_kedai_baru(p_kedai_id text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
  v_kedai kedai%ROWTYPE; v_pertama transaksi%ROWTYPE; v_kedua transaksi%ROWTYPE;
  v_bayar_terus text[] := ARRAY['tunai','transfer'];
  v_bayar double precision; v_consign double precision; v_anchor date;
  v_id_asas text; v_id_topup text; v_tarikh_pertama date; v_tarikh_kedua date;
BEGIN
  SELECT * INTO v_kedai FROM kedai WHERE id = p_kedai_id;
  IF NOT FOUND OR v_kedai.didaftarkan_oleh IS NULL THEN RETURN; END IF;

  SELECT * INTO v_pertama FROM transaksi WHERE kedai_id = p_kedai_id ORDER BY tarikh_masa ASC LIMIT 1;
  IF NOT FOUND THEN RETURN; END IF;

  SELECT COALESCE(upah_kedai_baru_bayar,10), COALESCE(upah_kedai_baru_consignment,2), COALESCE(bonus_anchor_tarikh, CURRENT_DATE)
    INTO v_bayar, v_consign, v_anchor FROM tetapan WHERE id = 1;

  v_id_asas := 'BKB-' || p_kedai_id || '-asas';
  v_id_topup := 'BKB-' || p_kedai_id || '-topup';
  v_tarikh_pertama := (v_pertama.tarikh_masa AT TIME ZONE 'Asia/Kuala_Lumpur')::date;

  IF v_tarikh_pertama >= v_anchor AND NOT EXISTS (SELECT 1 FROM bonus_kedai_baru WHERE id = v_id_asas) THEN
    IF v_pertama.kaedah_bayaran = ANY(v_bayar_terus) THEN
      INSERT INTO bonus_kedai_baru (id, kedai_id, pekerja_id, label, jumlah, tarikh_diperolehi, tarikh_matang)
      VALUES (v_id_asas, p_kedai_id, v_kedai.didaftarkan_oleh, 'Bonus Kedai Baru', v_bayar, v_tarikh_pertama, kira_tarikh_matang_bonus(v_tarikh_pertama, v_anchor));
    ELSE
      INSERT INTO bonus_kedai_baru (id, kedai_id, pekerja_id, label, jumlah, tarikh_diperolehi, tarikh_matang)
      VALUES (v_id_asas, p_kedai_id, v_kedai.didaftarkan_oleh, 'Bonus Kedai Baru (Consignment/Hutang)', v_consign, v_tarikh_pertama, kira_tarikh_matang_bonus(v_tarikh_pertama, v_anchor));
    END IF;
  END IF;

  IF v_pertama.kaedah_bayaran <> ALL(v_bayar_terus) AND NOT EXISTS (SELECT 1 FROM bonus_kedai_baru WHERE id = v_id_topup) THEN
    SELECT * INTO v_kedua FROM transaksi WHERE kedai_id = p_kedai_id AND id <> v_pertama.id AND kaedah_bayaran = ANY(v_bayar_terus)
      ORDER BY tarikh_masa ASC LIMIT 1;
    IF FOUND THEN
      v_tarikh_kedua := (v_kedua.tarikh_masa AT TIME ZONE 'Asia/Kuala_Lumpur')::date;
      IF v_tarikh_kedua >= v_anchor AND GREATEST(v_bayar - v_consign, 0) > 0 THEN
        INSERT INTO bonus_kedai_baru (id, kedai_id, pekerja_id, label, jumlah, tarikh_diperolehi, tarikh_matang)
        VALUES (v_id_topup, p_kedai_id, v_kedai.didaftarkan_oleh, 'Bonus Kedai Baru (Top-up Belian Tunai)', GREATEST(v_bayar - v_consign, 0), v_tarikh_kedua, kira_tarikh_matang_bonus(v_tarikh_kedua, v_anchor));
      END IF;
    END IF;
  END IF;
END;
$function$;

-- 6. Panggil sync selepas setiap transaksi kedai direkod (submit_penghantaran, signature
--    TAK berubah — CREATE OR REPLACE cukup, tiada DROP diperlukan).
CREATE OR REPLACE FUNCTION public.submit_penghantaran(p_id text, p_kedai_id text, p_items jsonb, p_jumlah double precision, p_status text, p_nota text, p_resit text, p_jarak_km double precision DEFAULT 0, p_nama_pembeli text DEFAULT NULL::text, p_kaedah_bayaran text DEFAULT 'tunai'::text, p_jumlah_asal double precision DEFAULT NULL::double precision, p_diskaun_peratus double precision DEFAULT 0, p_resit_bukti_url text DEFAULT NULL::text, p_pekerja_id_override uuid DEFAULT NULL::uuid, p_tarikh_masa timestamptz DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE item jsonb; v_pekerja_id uuid; v_tarikh_masa timestamptz;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid()) THEN
    RAISE EXCEPTION 'Tidak dibenarkan';
  END IF;

  v_pekerja_id := CASE WHEN p_pekerja_id_override IS NOT NULL AND is_pemilik() THEN p_pekerja_id_override ELSE auth.uid() END;
  v_tarikh_masa := CASE WHEN p_tarikh_masa IS NOT NULL AND is_pemilik() THEN p_tarikh_masa ELSE now() END;

  FOR item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    UPDATE stok_pekerja SET kuantiti = kuantiti - (item->>'qty')::int
      WHERE pekerja_id = v_pekerja_id AND stok_id = item->>'stokId' AND kuantiti >= (item->>'qty')::int;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Stok bawaan tidak mencukupi untuk %', item->>'stokId';
    END IF;
  END LOOP;

  INSERT INTO transaksi (id, kedai_id, nama_pembeli, items, jumlah, status, nota, resit, jarak_km, created_by, kaedah_bayaran, jumlah_asal, diskaun_peratus, jualan_disahkan, resit_bukti_url, tarikh_masa)
  VALUES (p_id, p_kedai_id, p_nama_pembeli, p_items, p_jumlah, p_status, p_nota, p_resit, p_jarak_km, v_pekerja_id::text, p_kaedah_bayaran, COALESCE(p_jumlah_asal, p_jumlah), p_diskaun_peratus, (p_kaedah_bayaran <> 'consignment'), p_resit_bukti_url, v_tarikh_masa);

  UPDATE kedai SET
    hutang = hutang + (CASE WHEN p_status = 'hutang' THEN p_jumlah ELSE 0 END),
    last_visit = CURRENT_DATE::text
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

-- 7. Pemilik tick bayar — SEMUA bonus MATANG (tarikh_matang <= hari ini) utk 1 pekerja
--    sekaligus. Boleh sekalikan dgn baucar upah_harian hari ini (tambah jumlah terus),
--    atau cipta baucar 'bonus_kedai' berasingan (status draf, ikut UI kelulusan sedia ada).
CREATE OR REPLACE FUNCTION public.bayar_bonus_kedai_terkumpul(p_pekerja_id uuid, p_gabung_baucar boolean DEFAULT false)
RETURNS double precision
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE v_jumlah double precision; v_tarikh date; v_baucar_id text; v_no_siri text;
BEGIN
  IF NOT is_pemilik() THEN RAISE EXCEPTION 'Hanya pemilik boleh sahkan bayaran bonus'; END IF;

  SELECT COALESCE(SUM(jumlah),0) INTO v_jumlah FROM bonus_kedai_baru
    WHERE pekerja_id = p_pekerja_id AND status = 'belum_dibayar' AND tarikh_matang <= CURRENT_DATE;
  IF v_jumlah <= 0 THEN RAISE EXCEPTION 'Tiada bonus matang untuk dibayar'; END IF;

  v_tarikh := (now() AT TIME ZONE 'Asia/Kuala_Lumpur')::date;

  IF p_gabung_baucar THEN
    SELECT id INTO v_baucar_id FROM baucar_bayaran WHERE pekerja_id = p_pekerja_id AND kategori = 'upah_harian' AND tarikh = v_tarikh;
    IF v_baucar_id IS NOT NULL THEN
      UPDATE baucar_bayaran SET jumlah = jumlah + v_jumlah, baki = COALESCE(baki,0) + v_jumlah,
        butiran = COALESCE(butiran,'{}'::jsonb) || jsonb_build_object('bonusKedaiDibayar', v_jumlah)
        WHERE id = v_baucar_id;
    ELSE
      v_baucar_id := gen_random_uuid()::text;
      v_no_siri := 'PV-' || extract(year from now())::text || '-' || lpad(nextval('baucar_siri_seq')::text, 4, '0');
      INSERT INTO baucar_bayaran (id, no_siri, pekerja_id, kategori, bulan, tarikh, jumlah, cash_ditangan, baki, tujuan, butiran)
      VALUES (v_baucar_id, v_no_siri, p_pekerja_id, 'upah_harian', to_char(v_tarikh,'YYYY-MM'), v_tarikh, v_jumlah, 0, v_jumlah,
        'Upah harian ' || to_char(v_tarikh,'DD/MM/YYYY'), jsonb_build_object('bonusKedaiDibayar', v_jumlah));
    END IF;
  ELSE
    v_baucar_id := gen_random_uuid()::text;
    v_no_siri := 'PV-' || extract(year from now())::text || '-' || lpad(nextval('baucar_siri_seq')::text, 4, '0');
    INSERT INTO baucar_bayaran (id, no_siri, pekerja_id, kategori, bulan, tarikh, jumlah, tujuan)
    VALUES (v_baucar_id, v_no_siri, p_pekerja_id, 'bonus_kedai', to_char(v_tarikh,'YYYY-MM'), v_tarikh, v_jumlah,
      'Bonus Kedai Baru Terkumpul (' || to_char(v_tarikh,'DD/MM/YYYY') || ')');
  END IF;

  UPDATE bonus_kedai_baru SET status = 'dibayar', dibayar_pada = now(), baucar_id = v_baucar_id
    WHERE pekerja_id = p_pekerja_id AND status = 'belum_dibayar' AND tarikh_matang <= CURRENT_DATE;

  RETURN v_jumlah;
END;
$function$;
