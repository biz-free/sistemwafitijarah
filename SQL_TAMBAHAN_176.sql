-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 176: Pindahan stok antara pekerja PERLU PENERIMA SAHKAN.
-- STATUS: DRAF — BELUM DIJALANKAN. Jalankan hanya selepas Amirul lulus.
-- Pelan: /home/claudebot/work/pelan-pindah-stok-terima.md
--
-- Sebelum ini pindah_stok_pekerja() (pemilik sahaja) terus menambah stok
-- penerima & log 'disahkan' — penerima tak tahu & tak perlu setuju (kes Nadia,
-- 24 unit, 2 Nov 2026).
--
-- Aliran baharu:
--  1. Pemilik pindah: stok DITOLAK dari sumber serta-merta (ditahan), log
--     'pindah_keluar' = disahkan (stok memang sudah keluar dari beg sumber),
--     log 'pindah_masuk' = MENUNGGU (stok penerima BELUM bertambah).
--  2. Penerima tekan Terima -> stok_pekerja penerima +qty, 'pindah_masuk' disahkan.
--     Penerima tekan Tolak / pemilik Batal / auto-batal 3 hari -> stok pulang ke
--     sumber, KEDUA-DUA log jadi 'ditolak' (sebab: ditolak_penerima /
--     dibatal_pemilik / dibatal_auto).
--  Semua pengiraan baki sedia ada tapis status='disahkan', jadi kekal seimbang:
--  semasa menunggu = sumber sudah tolak, penerima belum tambah.
--
-- TIDAK menyentuh data sedia ada (28 pindahan lama kekal 'disahkan').
-- Tiada perubahan pada pindahan lama; hanya 2 lajur baharu (nullable), 4 fungsi
-- baharu, 1 fungsi diganti, 2 trigger diganti (tambah syarat WHEN), 1 cron.
-- ═══════════════════════════════════════════════════════════

-- ── A. Lajur baharu ──
-- pasangan_id: pada baris 'pindah_masuk' = id baris 'pindah_keluar' pasangannya.
-- dilakukan_oleh: siapa (pemilik) yang memulakan pindahan (audit).
ALTER TABLE public.serahan_produk ADD COLUMN IF NOT EXISTS pasangan_id text;
ALTER TABLE public.serahan_produk ADD COLUMN IF NOT EXISTS dilakukan_oleh uuid REFERENCES auth.users(id);
CREATE INDEX IF NOT EXISTS idx_serahan_produk_dilakukan_oleh ON public.serahan_produk(dilakukan_oleh);

-- ── B. Trigger notifikasi sedia ada TIDAK patut menyala utk baris pindahan ──
-- trg_notify_pemilik_produk (INSERT) akan hantar kad Telegram Lulus/Tolak palsu
-- utk 'pindah_masuk' menunggu; trg_pemakluman_keputusan (UPDATE status) akan
-- umum keputusan palsu. Fungsi tidak diubah, hanya tambah syarat WHEN.
DROP TRIGGER IF EXISTS trg_notify_pemilik_produk ON public.serahan_produk;
CREATE TRIGGER trg_notify_pemilik_produk AFTER INSERT ON public.serahan_produk
  FOR EACH ROW WHEN (NEW.jenis NOT IN ('pindah_keluar','pindah_masuk'))
  EXECUTE FUNCTION notify_pemilik_kelulusan();

DROP TRIGGER IF EXISTS trg_pemakluman_keputusan ON public.serahan_produk;
CREATE TRIGGER trg_pemakluman_keputusan AFTER UPDATE OF status ON public.serahan_produk
  FOR EACH ROW WHEN (OLD.status IS DISTINCT FROM NEW.status
                     AND NEW.jenis NOT IN ('pindah_keluar','pindah_masuk'))
  EXECUTE FUNCTION pemakluman_keputusan();

-- ── C. pindah_stok_pekerja: kini cipta pindahan MENUNGGU ──
-- Tandatangan sama (uuid, uuid, text, int) -> kod HTML sedia ada tetap serasi.
CREATE OR REPLACE FUNCTION public.pindah_stok_pekerja(
  p_dari_pekerja_id uuid, p_kepada_pekerja_id uuid, p_stok_id text, p_qty int
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_nama text; v_keluar_id text; v_masuk_id text;
BEGIN
  IF NOT is_pemilik() THEN
    RAISE EXCEPTION 'Hanya pemilik boleh pindahkan stok bawaan pekerja';
  END IF;
  IF p_qty <= 0 THEN RAISE EXCEPTION 'Kuantiti mesti lebih 0'; END IF;
  IF p_dari_pekerja_id = p_kepada_pekerja_id THEN
    RAISE EXCEPTION 'Pekerja sumber dan destinasi mesti berbeza';
  END IF;

  -- Tahan stok daripada sumber (tidak boleh dijual dua kali)
  UPDATE stok_pekerja SET kuantiti = kuantiti - p_qty
    WHERE pekerja_id = p_dari_pekerja_id AND stok_id = p_stok_id AND kuantiti >= p_qty;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Stok bawaan pekerja sumber tidak mencukupi';
  END IF;

  SELECT nama INTO v_nama FROM stok WHERE id = p_stok_id;
  v_keluar_id := gen_random_uuid()::text;
  v_masuk_id  := gen_random_uuid()::text;

  INSERT INTO serahan_produk (id, pekerja_id, rujuk_pekerja_id, stok_id, stok_nama, kuantiti, jenis, status, dilakukan_oleh)
  VALUES (v_keluar_id, p_dari_pekerja_id, p_kepada_pekerja_id, p_stok_id, COALESCE(v_nama, p_stok_id), p_qty, 'pindah_keluar', 'disahkan', auth.uid());
  INSERT INTO serahan_produk (id, pekerja_id, rujuk_pekerja_id, stok_id, stok_nama, kuantiti, jenis, status, pasangan_id, dilakukan_oleh)
  VALUES (v_masuk_id, p_kepada_pekerja_id, p_dari_pekerja_id, p_stok_id, COALESCE(v_nama, p_stok_id), p_qty, 'pindah_masuk', 'menunggu', v_keluar_id, auth.uid());
END;
$$;
REVOKE EXECUTE ON FUNCTION public.pindah_stok_pekerja(uuid, uuid, text, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.pindah_stok_pekerja(uuid, uuid, text, int) TO authenticated;

-- ── D. Pembantu dalaman: batalkan pindahan menunggu & pulangkan stok ke sumber ──
CREATE OR REPLACE FUNCTION private.batalkan_pindahan(p_masuk_id text, p_sebab text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_m serahan_produk%ROWTYPE;
BEGIN
  SELECT * INTO v_m FROM serahan_produk
    WHERE id = p_masuk_id AND jenis = 'pindah_masuk' AND status = 'menunggu'
    FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pindahan tidak dijumpai atau sudah diputuskan';
  END IF;

  -- Pulangkan stok ke sumber (rujuk_pekerja_id pada baris masuk = pekerja sumber)
  INSERT INTO stok_pekerja (pekerja_id, stok_id, kuantiti)
  VALUES (v_m.rujuk_pekerja_id, v_m.stok_id, v_m.kuantiti)
  ON CONFLICT (pekerja_id, stok_id) DO UPDATE SET kuantiti = stok_pekerja.kuantiti + v_m.kuantiti;

  UPDATE serahan_produk
    SET status = 'ditolak', sebab = p_sebab, disahkan_oleh = auth.uid(), disahkan_pada = now()
    WHERE id IN (v_m.id, v_m.pasangan_id);
END;
$$;
REVOKE EXECUTE ON FUNCTION private.batalkan_pindahan(text, text) FROM PUBLIC, anon, authenticated;

-- ── E. Penerima: Terima ──
CREATE OR REPLACE FUNCTION public.terima_pindahan_stok(p_id text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_m serahan_produk%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Log masuk diperlukan'; END IF;
  SELECT * INTO v_m FROM serahan_produk
    WHERE id = p_id AND jenis = 'pindah_masuk' AND status = 'menunggu'
    FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Pindahan tidak dijumpai atau sudah diputuskan'; END IF;
  IF v_m.pekerja_id <> auth.uid() THEN
    RAISE EXCEPTION 'Hanya penerima pindahan boleh menerimanya';
  END IF;

  INSERT INTO stok_pekerja (pekerja_id, stok_id, kuantiti)
  VALUES (v_m.pekerja_id, v_m.stok_id, v_m.kuantiti)
  ON CONFLICT (pekerja_id, stok_id) DO UPDATE SET kuantiti = stok_pekerja.kuantiti + v_m.kuantiti;

  UPDATE serahan_produk
    SET status = 'disahkan', disahkan_oleh = auth.uid(), disahkan_pada = now()
    WHERE id = v_m.id;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.terima_pindahan_stok(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.terima_pindahan_stok(text) TO authenticated;

-- ── F. Penerima: Tolak ──
CREATE OR REPLACE FUNCTION public.tolak_pindahan_stok(p_id text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_pekerja uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Log masuk diperlukan'; END IF;
  SELECT pekerja_id INTO v_pekerja FROM serahan_produk
    WHERE id = p_id AND jenis = 'pindah_masuk' AND status = 'menunggu';
  IF NOT FOUND THEN RAISE EXCEPTION 'Pindahan tidak dijumpai atau sudah diputuskan'; END IF;
  IF v_pekerja <> auth.uid() THEN
    RAISE EXCEPTION 'Hanya penerima pindahan boleh menolaknya';
  END IF;
  PERFORM private.batalkan_pindahan(p_id, 'ditolak_penerima');
END;
$$;
REVOKE EXECUTE ON FUNCTION public.tolak_pindahan_stok(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.tolak_pindahan_stok(text) TO authenticated;

-- ── G. Pemilik: Batal ──
CREATE OR REPLACE FUNCTION public.batal_pindahan_stok(p_id text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_pemilik() THEN RAISE EXCEPTION 'Hanya pemilik boleh batalkan pindahan'; END IF;
  PERFORM private.batalkan_pindahan(p_id, 'dibatal_pemilik');
END;
$$;
REVOKE EXECUTE ON FUNCTION public.batal_pindahan_stok(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.batal_pindahan_stok(text) TO authenticated;

-- ── H. Auto-batal selepas 3 hari (pg_cron, 4:00 pagi MYT = 20:00 UTC) ──
CREATE OR REPLACE FUNCTION private.batal_auto_pindahan_stok() RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r record; n int := 0;
BEGIN
  FOR r IN SELECT id FROM serahan_produk
           WHERE jenis = 'pindah_masuk' AND status = 'menunggu'
             AND created_at < now() - interval '3 days'
  LOOP
    PERFORM private.batalkan_pindahan(r.id, 'dibatal_auto');
    n := n + 1;
  END LOOP;
  RETURN n;
END;
$$;
REVOKE EXECUTE ON FUNCTION private.batal_auto_pindahan_stok() FROM PUBLIC, anon, authenticated;

DO $$
BEGIN
  PERFORM cron.unschedule('batal-auto-pindahan-stok')
    WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'batal-auto-pindahan-stok');
  PERFORM cron.schedule('batal-auto-pindahan-stok', '0 20 * * *',
    $cron$SELECT private.batal_auto_pindahan_stok()$cron$);
END $$;

-- ── Semak selepas laksana (SELECT sahaja) ──
-- 1) SELECT jenis, status, count(*) FROM serahan_produk WHERE jenis LIKE 'pindah%' GROUP BY 1,2;
--    -> jangkaan: pindah_keluar/disahkan 28, pindah_masuk/disahkan 28 (tiada menunggu).
-- 2) SELECT jobname, schedule FROM cron.job WHERE jobname = 'batal-auto-pindahan-stok';
