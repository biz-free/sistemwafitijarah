-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 89: Permohonan Bayaran Hutang — pekerja boleh KUTIP
-- bayaran hutang drpd kedai (tunai/transfer) & hantar rekod, tapi ia
-- cuma diguna pakai (kedai.hutang berkurang, transaksi hutang lama
-- ditandakan selesai) SELEPAS pemilik sahkan. Sebelum ini "Terima
-- Bayaran Hutang" (rekod_bayaran RPC) 100% pemilik-sahaja — pekerja
-- LANGSUNG tiada akses (komen asal: "melibatkan kewangan"). Kini
-- pekerja BOLEH mohon, tapi pemilik kekal jadi get-keeper akhir —
-- elak pekerja "sahkan" bayaran tak sah sendiri.
--
-- Pemilik sendiri (is_pemilik()) yang hantar terus AUTO-DISAHKAN
-- (tiada sebab tunggu kelulusan sendiri) — sama pattern dgn
-- ambil_stok_pekerja.
-- ═══════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.permohonan_bayaran_hutang (
  id text PRIMARY KEY,
  kedai_id text NOT NULL REFERENCES public.kedai(id),
  pekerja_id uuid NOT NULL REFERENCES auth.users(id),
  jumlah double precision NOT NULL CHECK (jumlah > 0),
  kaedah_bayaran text NOT NULL CHECK (kaedah_bayaran IN ('tunai','transfer')),
  resit_bukti_url text,
  nota text,
  status text NOT NULL DEFAULT 'menunggu' CHECK (status IN ('menunggu','disahkan','ditolak')),
  disahkan_oleh uuid REFERENCES auth.users(id),
  disahkan_pada timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.permohonan_bayaran_hutang ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "pekerja hantar permohonan bayaran sendiri" ON public.permohonan_bayaran_hutang;
DROP POLICY IF EXISTS "staff lihat permohonan bayaran" ON public.permohonan_bayaran_hutang;
DROP POLICY IF EXISTS "pemilik urus semua permohonan bayaran" ON public.permohonan_bayaran_hutang;
CREATE POLICY "pekerja hantar permohonan bayaran sendiri" ON public.permohonan_bayaran_hutang FOR INSERT WITH CHECK (pekerja_id = auth.uid());
CREATE POLICY "staff lihat permohonan bayaran" ON public.permohonan_bayaran_hutang FOR SELECT USING (pekerja_id = auth.uid() OR is_pemilik());
CREATE POLICY "pemilik urus semua permohonan bayaran" ON public.permohonan_bayaran_hutang FOR UPDATE USING (is_pemilik());

-- Pekerja MOHON (atau pemilik terus, auto-lulus) — TIADA sentuhan kedai.hutang/
-- transaksi di sini bagi pekerja, cuma rekod permohonan menunggu.
CREATE OR REPLACE FUNCTION public.mohon_bayaran_hutang(p_id text, p_kedai_id text, p_jumlah double precision, p_kaedah_bayaran text, p_resit_bukti_url text DEFAULT NULL, p_nota text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Log masuk diperlukan'; END IF;
  IF p_jumlah <= 0 THEN RAISE EXCEPTION 'Jumlah mesti lebih 0'; END IF;
  IF p_kaedah_bayaran NOT IN ('tunai','transfer') THEN RAISE EXCEPTION 'Kaedah bayaran tidak sah'; END IF;

  IF is_pemilik() THEN
    PERFORM rekod_bayaran(p_kedai_id, p_jumlah);
    INSERT INTO permohonan_bayaran_hutang (id, kedai_id, pekerja_id, jumlah, kaedah_bayaran, resit_bukti_url, nota, status, disahkan_oleh, disahkan_pada)
    VALUES (p_id, p_kedai_id, auth.uid(), p_jumlah, p_kaedah_bayaran, p_resit_bukti_url, p_nota, 'disahkan', auth.uid(), now());
  ELSE
    INSERT INTO permohonan_bayaran_hutang (id, kedai_id, pekerja_id, jumlah, kaedah_bayaran, resit_bukti_url, nota)
    VALUES (p_id, p_kedai_id, auth.uid(), p_jumlah, p_kaedah_bayaran, p_resit_bukti_url, p_nota);
  END IF;
END;
$function$;

-- Pemilik putuskan — 'disahkan' baharu jalankan rekod_bayaran SEBENAR (kedai.hutang
-- berkurang + transaksi hutang lama ditanda selesai); 'ditolak' cuma tanda status.
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
    PERFORM rekod_bayaran(v_row.kedai_id, v_row.jumlah);
  END IF;

  UPDATE permohonan_bayaran_hutang SET status = p_status, disahkan_oleh = auth.uid(), disahkan_pada = now() WHERE id = p_id;
END;
$function$;

-- Sertakan dalam notifikasi kelulusan pemilik (sama corak spt serahan_cash/serahan_produk).
CREATE OR REPLACE FUNCTION public.notify_pemilik_kelulusan()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
  v_pekerja_nama text;
  v_jenis text;
  v_butiran text;
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
  ELSIF TG_TABLE_NAME = 'permohonan_cuti' THEN
    v_jenis := 'Permohonan Cuti/MC/Off';
    v_butiran := NEW.jenis || ' (' || to_char(NEW.tarikh_mula,'DD/MM/YYYY') || ' - ' || to_char(NEW.tarikh_tamat,'DD/MM/YYYY') || ')';
  ELSIF TG_TABLE_NAME = 'serahan_cash' THEN
    v_jenis := 'Serahan Duit Cash';
    v_butiran := 'RM' || NEW.jumlah;
  ELSIF TG_TABLE_NAME = 'serahan_produk' THEN
    v_jenis := CASE WHEN NEW.jenis = 'ambil' THEN 'Permohonan Ambil Stok' ELSE 'Serahan Produk Reject' END;
    v_butiran := NEW.stok_nama || ' ×' || NEW.kuantiti;
  ELSIF TG_TABLE_NAME = 'permohonan_bayaran_hutang' THEN
    v_jenis := 'Permohonan Bayaran Hutang';
    v_butiran := 'RM' || NEW.jumlah || ' (' || NEW.kaedah_bayaran || ')';
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
$function$;

DROP TRIGGER IF EXISTS trg_notify_pemilik_bayaran_hutang ON public.permohonan_bayaran_hutang;
CREATE TRIGGER trg_notify_pemilik_bayaran_hutang AFTER INSERT ON public.permohonan_bayaran_hutang
  FOR EACH ROW EXECUTE FUNCTION public.notify_pemilik_kelulusan();
