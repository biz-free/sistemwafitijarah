-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 155: Arkib + Pulih untuk kelulusan padam GENERIK
-- (kedai, pre_order, stok, baucar_bayaran, serahan_cash,
--  serahan_produk, pesanan_edagang) di Sistem Pengurusan (web).
--
-- Latar belakang kejadian: pemilik tersilap klik "Luluskan & Padam"
-- pada permohonan padam jenis 'pre_order' (Nizam Merbok Corner,
-- 27/9/26) — laluan web waktu itu terus sb.from(jadual).delete()
-- tanpa simpan salinan, jadi rekod hilang KEKAL tanpa cara pulih.
-- SQL_TAMBAHAN_154 dah ada private.arkib_padam + salin-sebelum-padam
-- utk laluan Telegram jenis 'transaksi' sahaja — fungsi di bawah
-- sambung corak yang sama utk jenis lain di laluan web.
--
-- padam_rekod_permohonan(): dipanggil oleh web SEBELUM padam.
--   Simpan snapshot penuh baris ke private.arkib_padam, kemudian
--   padam. Client (pekerja/pemilik) tiada akses terus ke skema
--   private, jadi ini WAJIB laluan RPC SECURITY DEFINER.
-- pulih_rekod_arkib_padam(): insert semula snapshot ke jadual asal
--   guna jsonb_populate_record (generik utk semua jadual whitelist).
--   Permohonan padam berkaitan (jika ada) ditanda balik 'ditolak'
--   supaya jelas ia sudah diundur.
--
-- Nama jadual sasaran TIDAK sekali-kali datang terus dari input
-- pengguna — dipeta melalui CASE whitelist supaya tiada suntikan
-- nama jadual sewenang-wenangnya.
--
-- CREATE ... IF NOT EXISTS di bawah sengaja diulang drpd SQL_TAMBAHAN_154
-- supaya fail ni boleh dijalankan berdiri sendiri walau 154 belum/sudah
-- dijalankan (idempoten, tiada kesan kalau jadual dah wujud).
-- ═══════════════════════════════════════════════════════════

CREATE SCHEMA IF NOT EXISTS private;

CREATE TABLE IF NOT EXISTS private.arkib_padam (
  id bigserial PRIMARY KEY,
  dicipta timestamptz NOT NULL DEFAULT now(),
  jadual text NOT NULL,
  rekod_id text NOT NULL,
  permohonan_id text,
  diputuskan_oleh uuid,
  data jsonb NOT NULL
);
ALTER TABLE private.arkib_padam ENABLE ROW LEVEL SECURITY;  -- tiada polisi = tiada akses terus (guna RPC SECURITY DEFINER sahaja)

CREATE OR REPLACE FUNCTION public.padam_rekod_permohonan(p_jenis text, p_rekod_id text, p_permohonan_id text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_data jsonb;
  v_jadual text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = v_uid AND role = 'pemilik') THEN
    RAISE EXCEPTION 'Hanya pemilik boleh meluluskan permohonan padam';
  END IF;

  v_jadual := CASE p_jenis
    WHEN 'kedai'           THEN 'kedai'
    WHEN 'pre_order'       THEN 'pre_order'
    WHEN 'stok'            THEN 'stok'
    WHEN 'baucar_bayaran'  THEN 'baucar_bayaran'
    WHEN 'serahan_cash'    THEN 'serahan_cash'
    WHEN 'serahan_produk'  THEN 'serahan_produk'
    WHEN 'pesanan_edagang' THEN 'pesanan_edagang'
    ELSE NULL
  END;
  IF v_jadual IS NULL THEN
    RAISE EXCEPTION 'Jenis "%" tidak disokong oleh padam_rekod_permohonan()', p_jenis;
  END IF;

  EXECUTE format('SELECT to_jsonb(t) FROM %I t WHERE id = $1', v_jadual) INTO v_data USING p_rekod_id;
  IF v_data IS NULL THEN
    RAISE EXCEPTION 'Rekod % sudah tiada dalam jadual %', p_rekod_id, v_jadual;
  END IF;

  INSERT INTO private.arkib_padam (jadual, rekod_id, permohonan_id, diputuskan_oleh, data)
  VALUES (v_jadual, p_rekod_id, p_permohonan_id, v_uid, v_data);

  EXECUTE format('DELETE FROM %I WHERE id = $1', v_jadual) USING p_rekod_id;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.padam_rekod_permohonan(text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.padam_rekod_permohonan(text, text, text) TO authenticated;


CREATE OR REPLACE FUNCTION public.pulih_rekod_arkib_padam(p_arkib_id bigint)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_a RECORD;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = v_uid AND role = 'pemilik') THEN
    RAISE EXCEPTION 'Hanya pemilik boleh memulihkan rekod';
  END IF;

  SELECT * INTO v_a FROM private.arkib_padam WHERE id = p_arkib_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Arkib tidak dijumpai'; END IF;

  EXECUTE format(
    'INSERT INTO %I SELECT * FROM jsonb_populate_record(NULL::%I, $1) ON CONFLICT (id) DO NOTHING',
    v_a.jadual, v_a.jadual
  ) USING v_a.data;

  IF v_a.permohonan_id IS NOT NULL THEN
    UPDATE permohonan_padam SET status = 'ditolak', diputuskan_oleh = v_uid, diputuskan_pada = now()
     WHERE id = v_a.permohonan_id AND status = 'diluluskan';
  END IF;

  RETURN v_a.jadual;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.pulih_rekod_arkib_padam(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.pulih_rekod_arkib_padam(bigint) TO authenticated;


CREATE OR REPLACE FUNCTION public.senarai_arkib_padam()
RETURNS TABLE (
  id bigint,
  dicipta timestamptz,
  jadual text,
  rekod_id text,
  permohonan_id text,
  diputuskan_oleh_nama text,
  label text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'pemilik') THEN
    RAISE EXCEPTION 'Hanya pemilik boleh lihat arkib padam';
  END IF;

  RETURN QUERY
  SELECT a.id, a.dicipta, a.jadual, a.rekod_id, a.permohonan_id,
         COALESCE(pr.nama, '?'),
         COALESCE(a.data->>'nama', a.data->>'kedai_nama', a.data->>'no_siri', a.data->>'resit', a.rekod_id)
    FROM private.arkib_padam a
    LEFT JOIN profiles pr ON pr.id = a.diputuskan_oleh
   ORDER BY a.dicipta DESC
   LIMIT 100;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.senarai_arkib_padam() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.senarai_arkib_padam() TO authenticated;
