-- ============================================================
-- SQL TAMBAHAN 168: Baiki flow bayaran hutang consignment
-- Hasil semakan flow 26 Okt 2026 (kes Coopmart PBH8407922). TIADA data diubah —
-- hanya 2 fungsi, 1 lajur baharu (nullable) dan 1 RPC baharu. Boleh dilaksana semula.
--
--  A. agih_bayaran_hutang (laluan Telegram) ikut susunan sama dgn rekod_bayaran (web):
--     invois yg jualannya SUDAH disahkan dibayar dulu, consignment belum disahkan di belakang.
--  B. Kad kelulusan Telegram utk bayaran hutang: papar nama kedai, invois hutang
--     terbuka, invois dipadankan, dan AMARAN jika ada consignment belum disahkan jualan.
--  C. Lajur permohonan_bayaran_hutang.transaksi_id (pilihan) + RPC pautkan_bayaran_invois
--     (pemilik sahaja) supaya bayaran boleh dipaut ke 1 invois. NOTA: pautan ini setakat
--     PAPARAN (kad Telegram/pengumuman). Ia BELUM mengubah cara wang diagih — itu perlu
--     ubah telegram_putuskan & rekod_bayaran (kerja berasingan, dengan kelulusan).
-- ============================================================

-- ---------- A. Susunan agihan seragam ----------
CREATE OR REPLACE FUNCTION public.agih_bayaran_hutang(p_kedai_id text, p_nama_pembeli text, p_jumlah double precision, p_tarikh_diterima date DEFAULT NULL::date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE baki float := p_jumlah; t RECORD; bayar float; hutang_baru float;
BEGIN
  IF p_jumlah IS NULL OR p_jumlah <= 0 THEN RAISE EXCEPTION 'Jumlah bayaran mesti lebih 0'; END IF;

  IF p_kedai_id IS NOT NULL THEN
    PERFORM pulih_diskaun_ikut_tarikh(p_kedai_id, p_jumlah, p_tarikh_diterima);
    UPDATE kedai SET hutang = GREATEST(0, hutang - p_jumlah) WHERE id = p_kedai_id
      RETURNING hutang INTO hutang_baru;
  END IF;

  FOR t IN
    SELECT id, jumlah, jumlah_dibayar FROM transaksi
    WHERE status = 'hutang'
      AND CASE WHEN p_kedai_id IS NOT NULL THEN kedai_id = p_kedai_id
               ELSE kedai_id IS NULL AND nama_pembeli = p_nama_pembeli END
    -- SAMA dgn rekod_bayaran(): consignment belum disahkan jualan dibayar PALING AKHIR
    ORDER BY (kaedah_bayaran = 'consignment' AND jualan_disahkan IS NOT TRUE) ASC, tarikh_masa ASC
    FOR UPDATE
  LOOP
    EXIT WHEN baki <= 0.005;
    bayar := LEAST(baki, GREATEST(t.jumlah - t.jumlah_dibayar, 0));
    UPDATE transaksi SET
      jumlah_dibayar = jumlah_dibayar + bayar,
      status = CASE WHEN jumlah_dibayar + bayar >= jumlah - 0.005 THEN 'selesai' ELSE status END
    WHERE id = t.id;
    baki := baki - bayar;
  END LOOP;

  IF p_kedai_id IS NOT NULL AND COALESCE(hutang_baru, 1) <= 0.005 THEN
    UPDATE transaksi SET status = 'selesai', jumlah_dibayar = GREATEST(jumlah_dibayar, jumlah)
    WHERE kedai_id = p_kedai_id AND status = 'hutang';
  END IF;
END;
$function$;

-- ---------- C (bahagian 1). Lajur pautan invois ----------
ALTER TABLE public.permohonan_bayaran_hutang
  ADD COLUMN IF NOT EXISTS transaksi_id text REFERENCES public.transaksi(id) ON DELETE SET NULL;

CREATE OR REPLACE FUNCTION public.pautkan_bayaran_invois(p_id text, p_transaksi_id text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_p permohonan_bayaran_hutang%ROWTYPE; v_t transaksi%ROWTYPE;
BEGIN
  IF NOT is_pemilik() THEN RAISE EXCEPTION 'Hanya pemilik boleh paut bayaran ke invois'; END IF;
  SELECT * INTO v_p FROM permohonan_bayaran_hutang WHERE id = p_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Rekod bayaran tidak dijumpai'; END IF;
  IF p_transaksi_id IS NOT NULL THEN
    SELECT * INTO v_t FROM transaksi WHERE id = p_transaksi_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Invois tidak dijumpai'; END IF;
    IF v_t.kedai_id IS DISTINCT FROM v_p.kedai_id THEN
      RAISE EXCEPTION 'Invois bukan milik kedai yang sama dengan bayaran ini';
    END IF;
  END IF;
  UPDATE permohonan_bayaran_hutang SET transaksi_id = p_transaksi_id WHERE id = p_id;
END;
$function$;
REVOKE ALL ON FUNCTION public.pautkan_bayaran_invois(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.pautkan_bayaran_invois(text, text) TO authenticated;

-- ---------- B. Kad Telegram bayaran hutang: nama kedai + invois + amaran ----------
-- Hanya cabang 'permohonan_bayaran_hutang' diubah; cabang lain SAMA seperti sebelum ini.
CREATE OR REPLACE FUNCTION public.notify_pemilik_kelulusan()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_pekerja_nama text;
  v_jenis text;
  v_butiran text;
  v_jenis_rekod text;
  v_kedai_nama text;
  v_senarai text;
  v_padan text;
  v_amaran text;
BEGIN
  IF TG_TABLE_NAME = 'serahan_produk' THEN
    IF NEW.status <> 'menunggu' THEN
      RETURN NEW;
    END IF;
    IF NEW.jenis = 'ambil' AND NEW.sebab IS NOT NULL THEN
      RETURN NEW;
    END IF;
  END IF;

  IF TG_TABLE_NAME = 'permohonan_bayaran_hutang' AND NEW.status <> 'menunggu' THEN
    RETURN NEW;
  END IF;

  SELECT nama INTO v_pekerja_nama FROM profiles WHERE id = NEW.pekerja_id;

  IF TG_TABLE_NAME = 'permohonan_padam' THEN
    v_jenis := 'Permohonan Padam';
    v_butiran := COALESCE(NEW.rekod_label, NEW.jenis) || COALESCE(' — Sebab: ' || NEW.sebab, '');
    v_jenis_rekod := 'permohonan_padam';
  ELSIF TG_TABLE_NAME = 'permohonan_cuti' THEN
    v_jenis := 'Permohonan Cuti/MC/Off';
    v_butiran := NEW.jenis || ' (' || to_char(NEW.tarikh_mula,'DD/MM/YYYY') || ' - ' || to_char(NEW.tarikh_tamat,'DD/MM/YYYY') || ')';
    v_jenis_rekod := 'permohonan_cuti';
  ELSIF TG_TABLE_NAME = 'serahan_cash' THEN
    v_jenis := 'Serahan Duit Cash';
    v_butiran := 'RM' || NEW.jumlah;
    v_jenis_rekod := 'serahan_cash';
  ELSIF TG_TABLE_NAME = 'serahan_produk' THEN
    v_jenis := CASE WHEN NEW.jenis = 'ambil' THEN 'Permohonan Ambil Stok' ELSE 'Serahan Produk Reject' END;
    v_butiran := NEW.stok_nama || ' ×' || NEW.kuantiti;
    v_jenis_rekod := 'serahan_produk';
  ELSIF TG_TABLE_NAME = 'permohonan_bayaran_hutang' THEN
    v_jenis := 'Permohonan Bayaran Hutang';
    v_butiran := 'RM' || NEW.jumlah || ' (' || NEW.kaedah_bayaran || ')';
    v_jenis_rekod := 'permohonan_bayaran_hutang';

    -- Maklumat tambahan (gagal senyap supaya notifikasi asal tidak terjejas)
    BEGIN
      IF NEW.kedai_id IS NOT NULL THEN
        SELECT nama INTO v_kedai_nama FROM kedai WHERE id = NEW.kedai_id;
        v_butiran := '🎯 ' || COALESCE(v_kedai_nama, NEW.kedai_id) || E'\n' || v_butiran;
        IF NEW.settlement_penuh THEN v_butiran := v_butiran || ' · PENUH'; END IF;
        IF NULLIF(NEW.nota, '') IS NOT NULL THEN v_butiran := v_butiran || E'\nNota: ' || NEW.nota; END IF;

        SELECT string_agg(id || ' RM' || to_char(jumlah - jumlah_dibayar, 'FM999990.00')
                 || ' (' || to_char(tarikh_masa AT TIME ZONE 'Asia/Kuala_Lumpur', 'DD/MM')
                 || CASE WHEN kaedah_bayaran = 'consignment' THEN ', consignment' ELSE '' END || ')',
               ', ' ORDER BY tarikh_masa)
          INTO v_senarai
          FROM transaksi WHERE kedai_id = NEW.kedai_id AND status = 'hutang';

        -- Invois dipadankan: pautan eksplisit dulu, jika tiada = SATU invois yg bakinya sama tepat dgn jumlah
        IF NEW.transaksi_id IS NOT NULL THEN
          v_padan := NEW.transaksi_id || ' (dipaut)';
        ELSE
          SELECT CASE WHEN count(*) = 1 THEN min(id) || ' (padanan jumlah, bukan pautan sistem)' END INTO v_padan
            FROM transaksi
            WHERE kedai_id = NEW.kedai_id AND status = 'hutang'
              AND abs((jumlah - jumlah_dibayar) - NEW.jumlah) < 0.01;
        END IF;
        IF v_padan IS NOT NULL THEN v_butiran := v_butiran || E'\n🧾 Invois: ' || v_padan; END IF;
        IF v_senarai IS NOT NULL THEN v_butiran := v_butiran || E'\n📌 Hutang terbuka: ' || v_senarai; END IF;

        SELECT string_agg(id, ', ' ORDER BY tarikh_masa) INTO v_amaran
          FROM transaksi
          WHERE kedai_id = NEW.kedai_id AND status = 'hutang'
            AND kaedah_bayaran = 'consignment' AND jualan_disahkan IS NOT TRUE;
        IF v_amaran IS NOT NULL THEN
          v_butiran := v_butiran || E'\n⚠️ Jualan consignment belum disahkan: ' || v_amaran
            || E'\n(lulus akan tutup invois tanpa rekod terjual — minta pekerja kemaskini jualan)';
        END IF;
      END IF;
    EXCEPTION WHEN others THEN
      RAISE WARNING '[notify_pemilik_kelulusan] butiran tambahan gagal utk %: %', NEW.id, SQLERRM;
    END;
  ELSE
    RETURN NEW;
  END IF;

  PERFORM net.http_post(
    url := 'https://smepriytkoxkmpvjvvzq.supabase.co/functions/v1/notifikasi-kelulusan-pemilik',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNtZXByaXl0a294a21wdmp2dnpxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMzODE1OTcsImV4cCI6MjA5ODk1NzU5N30.bLDjFNZ_gMm9ufCkA4TeFbw1rysuLnlQN-qW_WW0zr8'
    ),
    body := jsonb_build_object(
      'jenis', v_jenis, 'pekerja_nama', COALESCE(v_pekerja_nama, '?'), 'butiran', v_butiran,
      'record_id', NEW.id, 'jenis_rekod', v_jenis_rekod
    )
  );
  RETURN NEW;
END;
$function$;

-- Pengesahan (SELECT sahaja) selepas dilaksana:
--   select proname from pg_proc where proname in ('agih_bayaran_hutang','pautkan_bayaran_invois','notify_pemilik_kelulusan');
--   select column_name from information_schema.columns where table_name='permohonan_bayaran_hutang' and column_name='transaksi_id';
