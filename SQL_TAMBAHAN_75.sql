-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 75: Fix "Request Stok Mobile" — pekerja tak boleh
-- hantar WhatsApp kepada pemilik.
--
-- PUNCA SEBENAR: RLS "profiles" hanya benarkan (1) pemilik baca
-- SEMUA profil, atau (2) sesiapa baca PROFIL SENDIRI sahaja — tiada
-- polisi langsung utk pekerja baca profil PEMILIK. Jadi
-- sb.from('profiles').select('telefon').eq('role','pemilik')...
-- yang dipanggil oleh pekerja pulang KOSONG (bukan ralat — RLS
-- senyap tapis keluar), no. telefon jadi kosong, WhatsApp tak
-- pernah dibuka. Fix window.open() (popup-block) sebelum ini betul
-- tapi bukan punca sebenar isu — ini yang sebenarnya sekat.
--
-- Fix: RPC SECURITY DEFINER sempit yang HANYA dedah no. telefon
-- pemilik (bukan data lain), boleh dipanggil sesiapa log masuk —
-- corak sama seperti papan_jualan_pekerja_hari_ini (RLS profiles
-- sengaja ketat, RPC ni bukaan terkawal utk keperluan spesifik).
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.ambil_telefon_pemilik()
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_tel text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Log masuk diperlukan'; END IF;
  SELECT telefon INTO v_tel FROM profiles WHERE role = 'pemilik' LIMIT 1;
  RETURN v_tel;
END;
$$;
GRANT EXECUTE ON FUNCTION public.ambil_telefon_pemilik() TO authenticated;
