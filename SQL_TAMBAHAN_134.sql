-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 134: Pelarasan Kos Pekerja — pulih automatik upah/minyak bila
-- transaksi dipadam SELEPAS baucar harian pekerja tu dah DILULUSKAN/DIBAYAR
-- (cth: kedai pulangkan/batal pesanan lepas duit dah masuk kira upah pekerja).
--
-- MASALAH SEBELUM NI: padam_transaksi_kedai() terus SET status='dibatalkan' pada
-- baucar_bayaran (kategori upah_harian) hari berkenaan — tapi jika baucar tu dah
-- diluluskan/dibayar, duit SEBENAR dah/hampir dipindah kpd pekerja. Membatalkan
-- rekod baucar tak "tarik balik" duit tu, cuma buat rekod jadi tak konsisten dgn
-- realiti (kelihatan macam tak pernah dibayar walhal dah dibayar).
--
-- PENYELESAIAN: baucar lama DIKEKALKAN status asal (audit trail utuh, duit yg dah
-- dibayar tak "hilang" dari rekod). Kos upah+minyak transaksi yg dipadam direkod di
-- jadual `pelarasan_kos_pekerja` (belum_diselaraskan), lalu DITOLAK automatik drpd
-- baucar HARIAN SETERUSNYA pekerja yg sama (cipta_baucar_harian) — "kos hari ni
-- dipulihkan drpd baucar akan datang", bukan mengubah baucar lama.
-- ═══════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS pelarasan_kos_pekerja (
  id text PRIMARY KEY,
  pekerja_id uuid NOT NULL REFERENCES profiles(id),
  transaksi_id text,
  kedai_nama text,
  sebab text,
  jumlah_upah numeric NOT NULL DEFAULT 0,
  jumlah_minyak numeric NOT NULL DEFAULT 0,
  jumlah_total numeric GENERATED ALWAYS AS (jumlah_upah + jumlah_minyak) STORED,
  status text NOT NULL DEFAULT 'belum_diselaraskan' CHECK (status IN ('belum_diselaraskan','sudah_diselaraskan')),
  baucar_id text REFERENCES baucar_bayaran(id),
  tarikh_asal date,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE pelarasan_kos_pekerja ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pelarasan_pemilik_select ON pelarasan_kos_pekerja;
CREATE POLICY pelarasan_pemilik_select ON pelarasan_kos_pekerja FOR SELECT USING (is_pemilik());

DROP POLICY IF EXISTS pelarasan_pekerja_select ON pelarasan_kos_pekerja;
CREATE POLICY pelarasan_pekerja_select ON pelarasan_kos_pekerja FOR SELECT USING (pekerja_id = auth.uid());

-- Tiada policy INSERT/UPDATE/DELETE client-side langsung — hanya RPC SECURITY
-- DEFINER (padam_transaksi_kedai menulis, cipta_baucar_harian menanda "diselaraskan")
-- yang sentuh jadual ni, sama corak dgn baucar_bayaran.

-- ───────────────────────────────────────────────────────────
-- padam_transaksi_kedai — tambah param p_kos_minyak_pulih (dikira client-side, JS
-- sahaja ada logik laluan/haversine sesi kehadiran) + pulangkan jsonb (dulu void)
-- supaya UI boleh maklum pemilik bila pelarasan dicipta. DROP wajib (tandatangan &
-- jenis pulangan berubah — CREATE OR REPLACE gagal). GRANT EXECUTE mesti diulang
-- selepas DROP+CREATE (lihat nota SQL_TAMBAHAN_133 — DROP buang GRANT sedia ada).
-- ───────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.padam_transaksi_kedai(text);

CREATE OR REPLACE FUNCTION public.padam_transaksi_kedai(p_id text, p_kos_minyak_pulih numeric DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_trx RECORD; item jsonb; v_pekerja_id uuid; v_nama text; v_qty int;
  v_upah_trx numeric := 0; v_kedai_nama text; v_baucar_status text; v_hasil jsonb;
BEGIN
  IF NOT is_pemilik() THEN RAISE EXCEPTION 'Hanya pemilik boleh padam transaksi'; END IF;

  SELECT * INTO v_trx FROM transaksi WHERE id = p_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Transaksi tidak dijumpai'; END IF;

  BEGIN
    v_pekerja_id := v_trx.created_by::uuid;
  EXCEPTION WHEN others THEN
    v_pekerja_id := NULL;
  END;

  FOR item IN SELECT * FROM jsonb_array_elements(v_trx.items) LOOP
    v_qty := (item->>'qty')::int;
    IF v_pekerja_id IS NOT NULL THEN
      INSERT INTO stok_pekerja (pekerja_id, stok_id, kuantiti) VALUES (v_pekerja_id, item->>'stokId', v_qty)
        ON CONFLICT (pekerja_id, stok_id) DO UPDATE SET kuantiti = stok_pekerja.kuantiti + v_qty;
      SELECT nama INTO v_nama FROM stok WHERE id = item->>'stokId';
      INSERT INTO serahan_produk (id, pekerja_id, stok_id, stok_nama, kuantiti, jenis, status)
        VALUES (gen_random_uuid()::text, v_pekerja_id, item->>'stokId', COALESCE(v_nama, item->>'stokId'), v_qty, 'padam_pulang', 'disahkan');
    ELSE
      UPDATE stok SET stok = stok + v_qty WHERE id = item->>'stokId';
    END IF;
  END LOOP;

  IF v_trx.status = 'hutang' AND v_trx.kedai_id IS NOT NULL THEN
    UPDATE kedai SET hutang = GREATEST(0, hutang - v_trx.jumlah) WHERE id = v_trx.kedai_id;
  END IF;

  -- Kos upah pekerja bagi transaksi ni — kaedah sama spt jumlahUpahTransaksi() client-side.
  SELECT COALESCE(SUM((item->>'qty')::numeric * COALESCE(s.upah_pekerja, 0)), 0) INTO v_upah_trx
    FROM jsonb_array_elements(
      CASE WHEN v_trx.kaedah_bayaran = 'consignment' AND v_trx.items_terjual IS NOT NULL
           THEN v_trx.items_terjual ELSE v_trx.items END
    ) item
    LEFT JOIN stok s ON s.id = item->>'stokId';

  v_hasil := jsonb_build_object('pelarasan_dicipta', false);

  -- Kalau baucar HARIAN pekerja+tarikh ni dah DILULUSKAN/DIBAYAR (dikunci — tak
  -- ditimpa semula, lihat cipta_baucar_harian), kos upah+minyak transaksi ni dah
  -- TERLANJUR dibayar/diluluskan walaupun transaksi kini dipadam. Rekod kos ni utk
  -- DITOLAK drpd baucar HARIAN SETERUSNYA pekerja yg sama — baucar lama tak disentuh.
  IF v_pekerja_id IS NOT NULL AND (v_upah_trx > 0 OR p_kos_minyak_pulih > 0) THEN
    SELECT status INTO v_baucar_status FROM baucar_bayaran
      WHERE pekerja_id = v_pekerja_id AND kategori = 'upah_harian'
        AND tarikh = (v_trx.tarikh_masa AT TIME ZONE 'Asia/Kuala_Lumpur')::date;
    IF v_baucar_status IN ('diluluskan','dibayar') THEN
      SELECT nama INTO v_kedai_nama FROM kedai WHERE id = v_trx.kedai_id;
      INSERT INTO pelarasan_kos_pekerja (id, pekerja_id, transaksi_id, kedai_nama, sebab, jumlah_upah, jumlah_minyak, tarikh_asal, created_by)
      VALUES (gen_random_uuid()::text, v_pekerja_id, p_id, v_kedai_nama,
        'Transaksi dipadam selepas baucar diluluskan (pulangan/batal kedai)',
        v_upah_trx, GREATEST(0, p_kos_minyak_pulih),
        (v_trx.tarikh_masa AT TIME ZONE 'Asia/Kuala_Lumpur')::date, auth.uid());
      v_hasil := jsonb_build_object('pelarasan_dicipta', true, 'jumlah_upah', v_upah_trx,
        'jumlah_minyak', GREATEST(0, p_kos_minyak_pulih), 'jumlah_pelarasan', v_upah_trx + GREATEST(0, p_kos_minyak_pulih));
    END IF;
  END IF;

  DELETE FROM transaksi WHERE id = p_id;
  RETURN v_hasil;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.padam_transaksi_kedai(text, numeric) TO authenticated;

-- ───────────────────────────────────────────────────────────
-- cipta_baucar_harian — tandatangan TAK berubah (CREATE OR REPLACE selamat, GRANT
-- kekal). Tambah: tolak jumlah pelarasan_kos_pekerja TERTUNGGAK pekerja ni (jika
-- ada) drpd upah sebelum kira baki, & tanda pelarasan tu "sudah_diselaraskan" —
-- TAPI hanya bila baucar draf ni betul2 ditulis (draf baharu atau draf sedia ada
-- yg masih blh ditimpa), bukan bila baucar hari tu dah dikunci (diluluskan/dibayar)
-- — elak pelarasan "hilang" tanpa pernah benar2 ditolak drpd mana2 baucar.
-- ───────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.cipta_baucar_harian(p_pekerja_id uuid, p_tarikh date DEFAULT NULL::date, p_jumlah double precision DEFAULT NULL::double precision, p_butiran jsonb DEFAULT NULL::jsonb)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_id text; v_no_siri text; v_sedia_id text; v_sedia_status text;
  v_upah double precision := 0; v_cash double precision := 0; v_baki double precision;
  v_bulan text; v_tarikh date;
  v_pelarasan double precision := 0; v_pelarasan_ids text[];
  v_butiran jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Log masuk diperlukan';
  END IF;
  IF NOT is_pemilik() AND p_pekerja_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Pekerja hanya boleh jana baucar harian untuk diri sendiri';
  END IF;

  v_tarikh := COALESCE(p_tarikh, (now() AT TIME ZONE 'Asia/Kuala_Lumpur')::date);
  v_bulan := to_char(v_tarikh, 'YYYY-MM');

  IF p_jumlah IS NOT NULL THEN
    v_upah := p_jumlah;
  ELSE
    SELECT COALESCE(SUM(
      (SELECT COALESCE(SUM((item->>'qty')::numeric * COALESCE(s.upah_pekerja, 0)), 0)
       FROM jsonb_array_elements(
         CASE WHEN t.kaedah_bayaran = 'consignment' AND NOT COALESCE(t.jualan_disahkan, false)
              THEN '[]'::jsonb
              ELSE COALESCE(t.items_terjual, t.items)
         END
       ) item
       LEFT JOIN stok s ON s.id = item->>'stokId')
    ), 0) INTO v_upah
    FROM transaksi t
    WHERE t.created_by = p_pekerja_id::text
      AND (t.tarikh_masa AT TIME ZONE 'Asia/Kuala_Lumpur')::date = v_tarikh;
  END IF;

  SELECT COALESCE(SUM(t.jumlah), 0) INTO v_cash
  FROM transaksi t
  WHERE t.created_by = p_pekerja_id::text
    AND (t.tarikh_masa AT TIME ZONE 'Asia/Kuala_Lumpur')::date = v_tarikh
    AND t.kaedah_bayaran = 'tunai' AND t.status = 'selesai';

  SELECT COALESCE(SUM(jumlah_total), 0), COALESCE(array_agg(id), '{}')
    INTO v_pelarasan, v_pelarasan_ids
    FROM pelarasan_kos_pekerja WHERE pekerja_id = p_pekerja_id AND status = 'belum_diselaraskan';
  v_upah := v_upah - v_pelarasan;

  v_baki := v_upah - v_cash;
  v_butiran := CASE WHEN v_pelarasan > 0 THEN COALESCE(p_butiran,'{}'::jsonb) || jsonb_build_object('pelarasan', v_pelarasan) ELSE p_butiran END;

  SELECT id, status INTO v_sedia_id, v_sedia_status FROM baucar_bayaran
    WHERE pekerja_id = p_pekerja_id AND kategori = 'upah_harian' AND tarikh = v_tarikh;

  IF v_sedia_id IS NOT NULL THEN
    IF v_sedia_status = 'draf' THEN
      UPDATE baucar_bayaran SET jumlah = v_upah, cash_ditangan = v_cash, baki = v_baki, butiran = COALESCE(v_butiran, butiran)
        WHERE id = v_sedia_id;
      IF array_length(v_pelarasan_ids,1) > 0 THEN
        UPDATE pelarasan_kos_pekerja SET status='sudah_diselaraskan', baucar_id = v_sedia_id WHERE id = ANY(v_pelarasan_ids);
      END IF;
    END IF;
    RETURN v_sedia_id;
  END IF;

  v_id := gen_random_uuid()::text;
  v_no_siri := 'PV-' || extract(year from now())::text || '-' || lpad(nextval('baucar_siri_seq')::text, 4, '0');
  INSERT INTO baucar_bayaran (id, no_siri, pekerja_id, kategori, bulan, tarikh, jumlah, cash_ditangan, baki, tujuan, butiran)
  VALUES (v_id, v_no_siri, p_pekerja_id, 'upah_harian', v_bulan, v_tarikh, v_upah, v_cash, v_baki,
    'Upah harian ' || to_char(v_tarikh, 'DD/MM/YYYY'), v_butiran);
  IF array_length(v_pelarasan_ids,1) > 0 THEN
    UPDATE pelarasan_kos_pekerja SET status='sudah_diselaraskan', baucar_id = v_id WHERE id = ANY(v_pelarasan_ids);
  END IF;
  RETURN v_id;
END;
$function$;
