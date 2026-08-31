-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 131: Kekalkan singkatan (acronym) huruf besar penuh
-- semasa seragamkan nama kedai (susulan #130) — cth "MSA", "KTM", "JMJ",
-- "BPJ", "RNF" dsb memang perlu kekal huruf besar sepenuhnya, bukan
-- "Msa"/"Ktm"/"Jmj". Perkataan pendek (2-4 huruf) yang ASALNYA ditaip
-- huruf besar sepenuhnya kini dikekalkan; perkataan lain terus Title Case
-- macam biasa.
--
-- (1) Fungsi smart_titlecase() — INITCAP tapi kekalkan token 2-4 huruf
--     yang asalnya huruf besar sepenuhnya.
-- (2) Trigger seragam_nama_kedai() (dibina #130) dikemaskini guna fungsi
--     baharu ni — kesan pada kedai BAHARU/nama diubah PADA MASA DEPAN juga.
-- (3) Betulkan 31 rekod kedai sedia ada yang #130 (INITCAP semata-mata)
--     tersalah tukar singkatan kepada Title Case biasa.
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.smart_titlecase(p_input text)
RETURNS text
LANGUAGE plpgsql
AS $function$
DECLARE
  v_words text[];
  v_out text[] := '{}';
  v_word text;
  v_core text;
BEGIN
  IF p_input IS NULL THEN RETURN NULL; END IF;
  v_words := regexp_split_to_array(trim(p_input), '\s+');
  FOREACH v_word IN ARRAY v_words LOOP
    v_core := regexp_replace(v_word, '[^A-Za-z]', '', 'g');
    IF length(v_core) BETWEEN 2 AND 4 AND v_core = upper(v_core) AND v_core ~ '[A-Z]' THEN
      v_out := array_append(v_out, v_word); -- singkatan — kekal spt asal
    ELSE
      v_out := array_append(v_out, INITCAP(v_word));
    END IF;
  END LOOP;
  RETURN array_to_string(v_out, ' ');
END;
$function$;

CREATE OR REPLACE FUNCTION public.seragam_nama_kedai()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.nama IS NOT NULL THEN
    NEW.nama := smart_titlecase(NEW.nama);
  END IF;
  RETURN NEW;
END;
$function$;

UPDATE kedai SET nama = 'AA YON Enterprise' WHERE id = 'K4437115';
UPDATE kedai SET nama = 'AAA Mutiara Teguh Bujang' WHERE id = 'K2760330';
UPDATE kedai SET nama = 'AAA Teguh Mutiara Ambangan Heights' WHERE id = 'K7208384';
UPDATE kedai SET nama = 'Agro Mart Peladang PPK Merbok' WHERE id = 'K2317752';
UPDATE kedai SET nama = 'AR Rayyan Freshmart' WHERE id = 'K2394997';
UPDATE kedai SET nama = 'AS Tegas Jaya Enterprise' WHERE id = 'K1414442';
UPDATE kedai SET nama = 'Dapoq SS Dayarasa Yan' WHERE id = 'K5429926';
UPDATE kedai SET nama = 'Farmasi NL Yan' WHERE id = 'K4224278';
UPDATE kedai SET nama = 'HM Merbok Empire' WHERE id = 'K2131966';
UPDATE kedai SET nama = 'JHF Food Mart' WHERE id = 'K7661123';
UPDATE kedai SET nama = 'JMJ Maju Enterprise Sdn Bhd' WHERE id = 'K1333733';
UPDATE kedai SET nama = 'JMS Supermart' WHERE id = 'K5625874';
UPDATE kedai SET nama = 'JMS Supermart Sungai Puyu' WHERE id = 'K7885273';
UPDATE kedai SET nama = 'Mamu KTM' WHERE id = 'K1183878';
UPDATE kedai SET nama = 'MCM Utara Trading' WHERE id = 'K9897167';
UPDATE kedai SET nama = 'MCM Utara Trading Guar Chempedak' WHERE id = 'K9351108';
UPDATE kedai SET nama = 'MFM MAJU Singkir' WHERE id = 'K6696419';
UPDATE kedai SET nama = 'Mutiara BPJ' WHERE id = 'K8711912';
UPDATE kedai SET nama = 'NA Cucoq Merbok' WHERE id = 'K2958159';
UPDATE kedai SET nama = 'NT Yen Jalan Yan' WHERE id = 'K4552716';
UPDATE kedai SET nama = 'Pasar Mini MSA' WHERE id = 'K4482109';
UPDATE kedai SET nama = 'Pasaraya Borong BK Bujang' WHERE id = 'K9631417';
UPDATE kedai SET nama = 'Pasaraya JMJ Kuala Ketil' WHERE id = 'K7508653';
UPDATE kedai SET nama = 'Pasaraya Mutiara (KIDA)' WHERE id = 'K4033641';
UPDATE kedai SET nama = 'Perniagaan ABC Satu Butterworth' WHERE id = 'K8036413';
UPDATE kedai SET nama = 'PKS Fresh Marketing' WHERE id = 'K1036538';
UPDATE kedai SET nama = 'Restoran ABC Butterworth' WHERE id = 'K8769302';
UPDATE kedai SET nama = 'RNF Mart' WHERE id = 'K0514267';
UPDATE kedai SET nama = 'Sarah BT Abdullah' WHERE id = 'K6337214';
UPDATE kedai SET nama = 'SMY Jelmas Baling' WHERE id = 'K8650078';
UPDATE kedai SET nama = 'YK Segar Padang Serai' WHERE id = 'K2369529';
