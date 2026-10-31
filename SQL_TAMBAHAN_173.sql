-- ============================================================
-- SQL TAMBAHAN 173: Request Stok Mobile -> kad kelulusan Telegram + amaran item gagal
-- Sebelum ini notify_pemilik_kelulusan() sengaja LANGKAU serahan_produk jenis 'ambil'
-- yg ada 'sebab' (SQL_TAMBAHAN_74: ketika itu notifikasi hanya via WhatsApp), jadi
-- pemilik TIADA kad Telegram utk Request Stok Mobile. TIADA data diubah — hanya
-- 2 fungsi. Boleh dilaksana semula.
--
--  A. notify_pemilik_kelulusan(): buang pengecualian di atas; kad Telegram (butang
--     Lulus/Tolak) kini dihantar utk setiap item berjaya, dgn baris 📅 jadual pick up.
--     Cabang lain SAMA seperti SQL_TAMBAHAN_168.
--  B. lapor_gagal_stok_mobile(p_gagal jsonb): dipanggil pelayar pekerja bila ada item
--     gagal (cth stok gudang tak cukup). Hantar 1 mesej amaran Telegram (tanpa butang
--     — item gagal tiada rekod utk diluluskan). Dilindungi: pengguna log masuk sahaja.
--     p_gagal = [{"nama":"Tamar Cocoa 450g","qty":48,"unit":"unit","ralat":"..."}]
-- ============================================================

-- ---------- A. Kad Telegram utk Request Stok Mobile ----------
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
    -- Request Stok Mobile (jenis 'ambil' + sebab diisi): sertakan jadual pick up
    IF NEW.jenis = 'ambil' AND NEW.sebab IS NOT NULL THEN
      v_butiran := v_butiran || E'\n📅 ' || NEW.sebab;
    END IF;
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

-- ---------- B. Amaran item gagal ----------
CREATE OR REPLACE FUNCTION public.lapor_gagal_stok_mobile(p_gagal jsonb, p_nota text DEFAULT NULL)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_nama text; v_baris text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Perlu log masuk'; END IF;
  IF p_gagal IS NULL OR jsonb_typeof(p_gagal) <> 'array' OR jsonb_array_length(p_gagal) = 0 THEN RETURN; END IF;
  SELECT nama INTO v_nama FROM profiles WHERE id = auth.uid();

  SELECT string_agg('- ' || left(COALESCE(g->>'nama','?'),80) || ' ×' || left(COALESCE(g->>'qty','?'),10)
           || ' ' || left(COALESCE(g->>'unit',''),20) || ' (' || left(COALESCE(g->>'ralat',''),120) || ')', E'\n')
    INTO v_baris
    FROM jsonb_array_elements(p_gagal) g;

  PERFORM net.http_post(
    url := 'https://smepriytkoxkmpvjvvzq.supabase.co/functions/v1/notifikasi-kelulusan-pemilik',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNtZXByaXl0a294a21wdmp2dnpxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMzODE1OTcsImV4cCI6MjA5ODk1NzU5N30.bLDjFNZ_gMm9ufCkA4TeFbw1rysuLnlQN-qW_WW0zr8'
    ),
    body := jsonb_build_object(
      'jenis', '⚠️ Request Stok Mobile — ITEM GAGAL',
      'pekerja_nama', COALESCE(v_nama, '?'),
      'butiran', COALESCE(left(p_nota,200) || E'\n', '') || v_baris || E'\n(tiada rekod dicipta — pekerja perlu request semula)'
    )
  );
END;
$function$;
REVOKE ALL ON FUNCTION public.lapor_gagal_stok_mobile(jsonb, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.lapor_gagal_stok_mobile(jsonb, text) TO authenticated;

-- Pengesahan (SELECT sahaja) selepas dilaksana:
--   select proname from pg_proc where proname in ('notify_pemilik_kelulusan','lapor_gagal_stok_mobile');
