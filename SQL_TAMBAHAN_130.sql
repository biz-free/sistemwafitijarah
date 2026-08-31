-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 130: Seragamkan nama kedai — Huruf Besar Awal Setiap
-- Perkataan (Title Case), cth "AA YON ENTERPRISE" -> "Aa Yon Enterprise",
-- "nabila goreng pisang sungai petani" -> "Nabila Goreng Pisang Sungai
-- Petani". Guna INITCAP() Postgres sedia ada.
--
-- (1) Kemaskini SEMUA 202 rekod kedai sedia ada sekali sahaja.
-- (2) Trigger BEFORE INSERT/UPDATE OF nama — apa-apa kedai BAHARU atau
--     nama kedai yang diubah PADA MASA DEPAN (dari mana-mana laluan:
--     daftar kedai baharu di apps, kemaskini profil kedai, dll) automatik
--     diseragamkan sama, tanpa perlu ubah kod client di setiap tempat.
--
-- NOTA: INITCAP tak kekalkan singkatan huruf besar penuh (cth "MSA" jadi
-- "Msa", "KTM" jadi "Ktm") — ini had biasa mana-mana fungsi title-case
-- automatik. Kalau ada nama tertentu nak dikekalkan huruf besar penuh
-- (singkatan syarikat dll), boleh dibetulkan manual selepas ini.
-- ═══════════════════════════════════════════════════════════

UPDATE kedai SET nama = INITCAP(nama) WHERE nama IS NOT NULL;

CREATE OR REPLACE FUNCTION public.seragam_nama_kedai()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.nama IS NOT NULL THEN
    NEW.nama := INITCAP(NEW.nama);
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_seragam_nama_kedai ON kedai;
CREATE TRIGGER trg_seragam_nama_kedai
BEFORE INSERT OR UPDATE OF nama ON kedai
FOR EACH ROW EXECUTE FUNCTION public.seragam_nama_kedai();
