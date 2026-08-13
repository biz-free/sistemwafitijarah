-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 100: Elak & bersihkan transaksi PENDUA (double-tap butang
-- "Sahkan & Rekod Penghantaran"). Pemilik minta "tempahan pendua padam
-- automatik" — siasatan tunjukkan jadual Tempahan (pre_order) sebenarnya
-- TIADA pendua, tapi jadual Transaksi (rekod penghantaran) ADA 3 pasangan
-- pendua tulen (0.6–4 saat antara satu sama lain).
--
-- PENTING: takrif "100% sama" MESTI ada HAD MASA (disahkan bersama pemilik)
-- — jumpa 1 kes serupa (kedai/produk/harga sama) tapi 16 HARI berbeza, iaitu
-- 2 jualan SAH berasingan, BUKAN pendua. Tanpa had masa, cleanup akan salah
-- padam jualan tulen.
--
-- (A) Bersihkan 3 pendua sedia ada (guna padam_transaksi_kedai() — pulangkan
--     stok bawaan & betulkan hutang kedai dgn betul, bukan DELETE terus).
-- (B) submit_penghantaran() kini SEKAT transaksi sama persis (kedai+items+
--     jumlah+kaedah bayaran+pekerja) dlm 5 minit — cegah pendua akan datang.
-- ═══════════════════════════════════════════════════════════

-- (A) Padam salinan KEDUA setiap pasangan pendua tulen, kekalkan yang PERTAMA.
SELECT padam_transaksi_kedai('T1365033'); -- pendua T1363769 (0.67 saat)
SELECT padam_transaksi_kedai('T7028065'); -- pendua T7025582 (4 saat, Cik Misai Jalan Yan)
SELECT padam_transaksi_kedai('T7907666'); -- pendua T7904231 (1.6 saat)

-- (B) Tambah sekatan pendua dlm submit_penghantaran() — signature TIDAK
-- berubah drpd SQL_TAMBAHAN_98, jadi CREATE OR REPLACE terus (tiada DROP perlu).
CREATE OR REPLACE FUNCTION public.submit_penghantaran(
  p_id text, p_kedai_id text, p_items jsonb, p_jumlah double precision, p_status text, p_nota text, p_resit text,
  p_jarak_km double precision DEFAULT 0, p_nama_pembeli text DEFAULT NULL::text, p_kaedah_bayaran text DEFAULT 'tunai'::text,
  p_jumlah_asal double precision DEFAULT NULL::double precision, p_diskaun_peratus double precision DEFAULT 0,
  p_resit_bukti_url text DEFAULT NULL::text, p_pekerja_id_override uuid DEFAULT NULL::uuid,
  p_tarikh_masa timestamp with time zone DEFAULT NULL::timestamp with time zone,
  p_tarikh_akhir_bayaran date DEFAULT NULL::date
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE item jsonb; v_pekerja_id uuid; v_tarikh_masa timestamptz;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid()) THEN
    RAISE EXCEPTION 'Tidak dibenarkan';
  END IF;

  v_pekerja_id := CASE WHEN p_pekerja_id_override IS NOT NULL AND is_pemilik() THEN p_pekerja_id_override ELSE auth.uid() END;
  v_tarikh_masa := CASE WHEN p_tarikh_masa IS NOT NULL AND is_pemilik() THEN p_tarikh_masa ELSE now() END;

  -- Sekat pendua double-tap: transaksi SAMA PERSIS (kedai, items, jumlah, kaedah
  -- bayaran, pekerja) tak boleh direkod 2x dlm 5 minit tarikh_masa yg sama.
  IF EXISTS (
    SELECT 1 FROM transaksi
    WHERE created_by = v_pekerja_id::text
      AND kedai_id IS NOT DISTINCT FROM p_kedai_id
      AND items = p_items
      AND jumlah = p_jumlah
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

  INSERT INTO transaksi (id, kedai_id, nama_pembeli, items, jumlah, status, nota, resit, jarak_km, created_by, kaedah_bayaran, jumlah_asal, diskaun_peratus, jualan_disahkan, resit_bukti_url, tarikh_masa, tarikh_akhir_bayaran)
  VALUES (p_id, p_kedai_id, p_nama_pembeli, p_items, p_jumlah, p_status, p_nota, p_resit, p_jarak_km, v_pekerja_id::text, p_kaedah_bayaran, COALESCE(p_jumlah_asal, p_jumlah), p_diskaun_peratus, (p_kaedah_bayaran <> 'consignment'), p_resit_bukti_url, v_tarikh_masa, p_tarikh_akhir_bayaran);

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
