-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 126: Senarai Semak Follow-up (Tab "📍 Perlu Servis" /
-- Urus Route) — pekerja tandakan status lepas follow-up WhatsApp:
--   ada_stok    ✅ Kedai masih ada produk (x perlu tambah)
--   nak_tambah  🛒 Kedai nak tambah produk
--   xreply      ⏳ Tidak reply — perlu follow-up lagi
--   xberminat   ❌ Tidak berminat
-- Kedai yang sudah ditandakan (dan belum ada lawatan sebenar sejak itu)
-- automatik "turun ke bawah" senarai supaya kedai yang belum diproses
-- kekal di atas. RLS `kedai` UPDATE cuma benarkan pemilik, jadi guna RPC
-- SECURITY DEFINER supaya pekerja pun boleh tandakan sendiri.
-- ═══════════════════════════════════════════════════════════

ALTER TABLE kedai ADD COLUMN IF NOT EXISTS followup_status text;
ALTER TABLE kedai ADD COLUMN IF NOT EXISTS followup_status_pada timestamptz;
ALTER TABLE kedai ADD COLUMN IF NOT EXISTS followup_status_oleh uuid REFERENCES profiles(id);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'kedai_followup_status_check') THEN
    ALTER TABLE kedai ADD CONSTRAINT kedai_followup_status_check
      CHECK (followup_status IS NULL OR followup_status IN ('ada_stok','nak_tambah','xreply','xberminat'));
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.tanda_followup_servis(p_kedai_id text, p_status text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Log masuk diperlukan';
  END IF;
  IF p_status IS NOT NULL AND p_status NOT IN ('ada_stok','nak_tambah','xreply','xberminat') THEN
    RAISE EXCEPTION 'Status follow-up tidak sah';
  END IF;

  UPDATE kedai SET
    followup_status = p_status,
    followup_status_pada = CASE WHEN p_status IS NULL THEN NULL ELSE now() END,
    followup_status_oleh = CASE WHEN p_status IS NULL THEN NULL ELSE auth.uid() END
  WHERE id = p_kedai_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Kedai tidak dijumpai';
  END IF;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.tanda_followup_servis(text, text) TO authenticated;
