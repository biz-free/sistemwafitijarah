-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 175: Restock gudang AUTO (toggle di Tab Stok > Gudang)
-- Bila ON: apabila stok produk AKTIF turun ke bawah ambang (lalai 50),
-- gudang ditambah terus ke sasaran (lalai 100) dan direkod dalam
-- serahan_produk (jenis 'restock', sebab 'Auto restock').
-- Lalai OFF. RPC restock_auto_imbas() = imbas produk yang sedia rendah.
-- ═══════════════════════════════════════════════════════════

ALTER TABLE public.tetapan
  ADD COLUMN IF NOT EXISTS restock_auto_aktif  boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS restock_auto_ambang integer NOT NULL DEFAULT 50,
  ADD COLUMN IF NOT EXISTS restock_auto_sasaran integer NOT NULL DEFAULT 100;

CREATE OR REPLACE FUNCTION public.trg_restock_auto()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE t record; v_pemilik uuid; v_tambah int;
BEGIN
  IF NEW.stok >= OLD.stok OR NEW.aktif IS NOT TRUE THEN RETURN NEW; END IF;
  SELECT restock_auto_aktif, restock_auto_ambang, restock_auto_sasaran INTO t FROM tetapan WHERE id = 1;
  IF NOT FOUND OR t.restock_auto_aktif IS NOT TRUE THEN RETURN NEW; END IF;
  IF NEW.stok >= t.restock_auto_ambang OR t.restock_auto_sasaran <= NEW.stok THEN RETURN NEW; END IF;

  SELECT id INTO v_pemilik FROM profiles WHERE role = 'pemilik' ORDER BY id LIMIT 1;
  IF v_pemilik IS NULL THEN RETURN NEW; END IF;

  v_tambah := t.restock_auto_sasaran - NEW.stok;
  NEW.stok := t.restock_auto_sasaran;
  INSERT INTO serahan_produk (id, pekerja_id, stok_id, stok_nama, kuantiti, jenis, sebab, status)
  VALUES (gen_random_uuid()::text, v_pemilik, NEW.id, NEW.nama, v_tambah, 'restock', 'Auto restock', 'disahkan');
  RETURN NEW;
END;
$function$;

CREATE TRIGGER trg_restock_auto BEFORE UPDATE OF stok ON public.stok
  FOR EACH ROW EXECUTE FUNCTION public.trg_restock_auto();

-- Imbas: restock produk aktif yang SEDIA di bawah ambang. Pemilik sahaja. Pulang bilangan produk.
CREATE OR REPLACE FUNCTION public.restock_auto_imbas()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE t record; r record; n int := 0;
BEGIN
  IF NOT is_pemilik() THEN RAISE EXCEPTION 'Hanya pemilik'; END IF;
  SELECT restock_auto_ambang, restock_auto_sasaran INTO t FROM tetapan WHERE id = 1;
  FOR r IN SELECT id, nama, stok FROM stok WHERE aktif IS NOT FALSE AND stok < t.restock_auto_ambang AND stok < t.restock_auto_sasaran LOOP
    UPDATE stok SET stok = t.restock_auto_sasaran WHERE id = r.id;
    INSERT INTO serahan_produk (id, pekerja_id, stok_id, stok_nama, kuantiti, jenis, sebab, status)
    VALUES (gen_random_uuid()::text, auth.uid(), r.id, r.nama, t.restock_auto_sasaran - r.stok, 'restock', 'Auto restock', 'disahkan');
    n := n + 1;
  END LOOP;
  RETURN n;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.restock_auto_imbas() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.restock_auto_imbas() TO authenticated;
