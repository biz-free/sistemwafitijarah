-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 65: Kelulusan pemilik utk pekerja ambil stok dari
-- gudang, + notifikasi emel automatik kepada pemilik bila-bila ada
-- permohonan baharu perlu kelulusan (padam/cuti/cash/produk).
-- ═══════════════════════════════════════════════════════════

-- ── 1) Ambil stok kini perlu kelulusan pemilik (pekerja) ──
-- ambil_stok_pekerja() KEKAL sedia ada — dipakai PEMILIK sahaja utk ambil stok
-- terus tanpa perlu sendiri lulus permohonan sendiri (tak masuk akal). Pekerja
-- kini guna 2 fungsi baharu: minta (tiada pergerakan stok berlaku), kemudian
-- pemilik putuskan (pergerakan stok SEBENAR hanya berlaku bila disahkan).

CREATE OR REPLACE FUNCTION public.minta_ambil_stok(p_id text, p_stok_id text, p_qty int) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_nama text; v_ada_stok int;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Log masuk diperlukan'; END IF;
  IF p_qty <= 0 THEN RAISE EXCEPTION 'Kuantiti mesti lebih 0'; END IF;
  SELECT stok, nama INTO v_ada_stok, v_nama FROM stok WHERE id = p_stok_id;
  IF v_ada_stok IS NULL THEN RAISE EXCEPTION 'Produk tidak dijumpai'; END IF;
  IF v_ada_stok < p_qty THEN RAISE EXCEPTION 'Stok gudang tidak mencukupi (baki: %)', v_ada_stok; END IF;
  INSERT INTO serahan_produk (id, pekerja_id, stok_id, stok_nama, kuantiti, jenis, status)
  VALUES (p_id, auth.uid(), p_stok_id, COALESCE(v_nama, p_stok_id), p_qty, 'ambil', 'menunggu');
END;
$$;
GRANT EXECUTE ON FUNCTION public.minta_ambil_stok(text, text, int) TO authenticated;

CREATE OR REPLACE FUNCTION public.putuskan_ambil_stok(p_id text, p_status text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_row serahan_produk%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Log masuk diperlukan'; END IF;
  IF NOT is_pemilik() THEN RAISE EXCEPTION 'Hanya pemilik boleh luluskan permohonan ambil stok'; END IF;
  IF p_status NOT IN ('disahkan','ditolak') THEN RAISE EXCEPTION 'Status tidak sah'; END IF;

  SELECT * INTO v_row FROM serahan_produk WHERE id = p_id AND jenis = 'ambil' AND status = 'menunggu';
  IF NOT FOUND THEN RAISE EXCEPTION 'Permohonan tidak dijumpai atau sudah diputuskan'; END IF;

  IF p_status = 'disahkan' THEN
    UPDATE stok SET stok = stok - v_row.kuantiti WHERE id = v_row.stok_id AND stok >= v_row.kuantiti;
    IF NOT FOUND THEN RAISE EXCEPTION 'Stok gudang tidak mencukupi lagi — mungkin sudah diambil/pindah sejak permohonan dihantar'; END IF;
    INSERT INTO stok_pekerja (pekerja_id, stok_id, kuantiti) VALUES (v_row.pekerja_id, v_row.stok_id, v_row.kuantiti)
      ON CONFLICT (pekerja_id, stok_id) DO UPDATE SET kuantiti = stok_pekerja.kuantiti + v_row.kuantiti;
  END IF;

  UPDATE serahan_produk SET status = p_status, disahkan_oleh = auth.uid(), disahkan_pada = now() WHERE id = p_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.putuskan_ambil_stok(text, text) TO authenticated;

-- ── 2) Notifikasi emel automatik kepada SEMUA akaun pemilik bila ada
-- permohonan BAHARU perlu kelulusan (padam/cuti/cash/produk reject & ambil) ──
-- Guna pg_net (async, tak lambatkan transaksi insert) panggil Edge Function
-- "notifikasi-kelulusan-pemilik" yang hantar emel melalui Resend (infra sedia
-- ada, sama macam hantar-emel-susulan). Anon key digunakan sebagai Authorization
-- (awam/tak sensitif, sama seperti dalam pengurusan.html) — function itu sendiri
-- guna SERVICE_ROLE_KEY dalamannya utk baca emel pemilik & hantar emel.
CREATE OR REPLACE FUNCTION public.notify_pemilik_kelulusan() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_pekerja_nama text;
  v_jenis text;
  v_butiran text;
BEGIN
  IF TG_TABLE_NAME = 'serahan_produk' AND NEW.status <> 'menunggu' THEN
    RETURN NEW; -- 'baik'/'restock'/ambil-oleh-pemilik auto-disahkan, tak perlu notifikasi
  END IF;

  SELECT nama INTO v_pekerja_nama FROM profiles WHERE id = NEW.pekerja_id;

  IF TG_TABLE_NAME = 'permohonan_padam' THEN
    v_jenis := 'Permohonan Padam';
    v_butiran := COALESCE(NEW.rekod_label, NEW.jenis) || COALESCE(' — Sebab: ' || NEW.sebab, '');
  ELSIF TG_TABLE_NAME = 'permohonan_cuti' THEN
    v_jenis := 'Permohonan Cuti/MC/Off';
    v_butiran := NEW.jenis || ' (' || to_char(NEW.tarikh_mula,'DD/MM/YYYY') || ' - ' || to_char(NEW.tarikh_tamat,'DD/MM/YYYY') || ')';
  ELSIF TG_TABLE_NAME = 'serahan_cash' THEN
    v_jenis := 'Serahan Duit Cash';
    v_butiran := 'RM' || NEW.jumlah;
  ELSIF TG_TABLE_NAME = 'serahan_produk' THEN
    v_jenis := CASE WHEN NEW.jenis = 'ambil' THEN 'Permohonan Ambil Stok' ELSE 'Serahan Produk Reject' END;
    v_butiran := NEW.stok_nama || ' ×' || NEW.kuantiti;
  ELSE
    RETURN NEW;
  END IF;

  PERFORM net.http_post(
    url := 'https://smepriytkoxkmpvjvvzq.supabase.co/functions/v1/notifikasi-kelulusan-pemilik',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNtZXByaXl0a294a21wdmp2dnpxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMzODE1OTcsImV4cCI6MjA5ODk1NzU5N30.bLDjFNZ_gMm9ufCkA4TeFbw1rysuLnlQN-qW_WW0zr8'
    ),
    body := jsonb_build_object('jenis', v_jenis, 'pekerja_nama', COALESCE(v_pekerja_nama, '?'), 'butiran', v_butiran)
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_pemilik_padam ON permohonan_padam;
CREATE TRIGGER trg_notify_pemilik_padam AFTER INSERT ON permohonan_padam
  FOR EACH ROW EXECUTE FUNCTION notify_pemilik_kelulusan();

DROP TRIGGER IF EXISTS trg_notify_pemilik_cuti ON permohonan_cuti;
CREATE TRIGGER trg_notify_pemilik_cuti AFTER INSERT ON permohonan_cuti
  FOR EACH ROW EXECUTE FUNCTION notify_pemilik_kelulusan();

DROP TRIGGER IF EXISTS trg_notify_pemilik_cash ON serahan_cash;
CREATE TRIGGER trg_notify_pemilik_cash AFTER INSERT ON serahan_cash
  FOR EACH ROW EXECUTE FUNCTION notify_pemilik_kelulusan();

DROP TRIGGER IF EXISTS trg_notify_pemilik_produk ON serahan_produk;
CREATE TRIGGER trg_notify_pemilik_produk AFTER INSERT ON serahan_produk
  FOR EACH ROW EXECUTE FUNCTION notify_pemilik_kelulusan();
