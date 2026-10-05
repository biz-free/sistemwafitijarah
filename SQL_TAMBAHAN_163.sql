-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 163: Pemakluman Telegram untuk permohonan affiliate baharu, dengan
-- kad "✅ Lulus" / "✕ Batal" (arahan Amirul 2026-10-05).
--
-- PUNCA: mohon_jadi_affiliate() (dipanggil borang affiliate.html) sudah sedia
-- INSERT ke affiliates (status='menunggu') tapi TIADA pemakluman kepada pemilik
-- langsung -- pemilik kena buka pengurusan.html sendiri untuk perasan permohonan
-- baharu. Jadual `serahan_cash`/`permohonan_cuti`/dll sudah ada trigger
-- notify_pemilik_kelulusan(), tapi affiliates TIDAK disambung kerana jadual tu
-- tiada lajur pekerja_id (fungsi kongsi sedia ada akan gagal kalau cuba sambung
-- terus -- SELECT ... WHERE id = NEW.pekerja_id akan pecah untuk affiliates).
--
-- PENYELESAIAN:
--   1. Trigger function BERASINGAN notify_pemilik_affiliate() (bukan ubah
--      notify_pemilik_kelulusan() yang dikongsi 5 jadual lain -- elak risiko
--      regresi kepada aliran kelulusan sedia ada).
--   2. telegram_putuskan() tambah cawangan 'affiliates': jana kod affiliate
--      automatik drpd perkataan pertama nama pemohon (huruf sahaja, huruf besar,
--      tambah angka kalau kod sudah dipakai), guna kadar_komisen_peratus/
--      kadar_diskaun_peratus/minima_belian YANG SUDAH ADA pada baris (nilai lalai
--      10/5/500 drpd mohon_jadi_affiliate() -- pemohon TIDAK boleh tetapkan sendiri).
--      Tolak = tolak_permohonan_affiliate() punya logik terus (tiada sebab, boleh
--      ubah kemudian di pengurusan.html jika perlu kemas kini kadar).
--      TIDAK panggil lulus_permohonan_affiliate()/tolak_permohonan_affiliate()
--      terus kerana kedua-dua RPC tu perlukan is_pemilik() (auth.uid()) yang
--      TIADA dlm konteks service_role Telegram -- UPDATE terus macam cawangan
--      lain dlm telegram_putuskan().
--   3. notifikasi-kelulusan-pemilik/index.ts & telegram-webhook/index.ts: tambah
--      kod "af" -> jadual "affiliates" (padan kedua-dua fail, lihat nota
--      SQL_TAMBAHAN_146), label butang "✕ Batal" (bukan "Tolak", ikut arahan
--      Amirul "kad lulus dan batal").
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.notify_pemilik_affiliate()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM net.http_post(
    url := 'https://smepriytkoxkmpvjvvzq.supabase.co/functions/v1/notifikasi-kelulusan-pemilik',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNtZXByaXl0a294a21wdmp2dnpxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMzODE1OTcsImV4cCI6MjA5ODk1NzU5N30.bLDjFNZ_gMm9ufCkA4TeFbw1rysuLnlQN-qW_WW0zr8'
    ),
    body := jsonb_build_object(
      'jenis', 'Permohonan Affiliate Baharu',
      'pekerja_nama', NEW.nama,
      'butiran', NEW.telefon || COALESCE(' — ' || NEW.cara_promosi, ''),
      'record_id', NEW.id,
      'jenis_rekod', 'affiliate'
    )
  );
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_notify_pemilik_affiliate ON public.affiliates;
CREATE TRIGGER trg_notify_pemilik_affiliate
  AFTER INSERT ON public.affiliates
  FOR EACH ROW
  WHEN (NEW.status = 'menunggu')
  EXECUTE FUNCTION public.notify_pemilik_affiliate();

-- ── telegram_putuskan(): tambah cawangan 'affiliates' (badan penuh disalin drpd
-- definisi hidup semasa, hanya tambah SATU cawangan ELSIF baharu) ──
CREATE OR REPLACE FUNCTION public.telegram_putuskan(p_admin_chat_id bigint, p_jadual text, p_id text, p_status text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_admin_user_id uuid;
  v_ok boolean;
  v_row RECORD;
  v_kod text;
  v_kod_cuba text;
  v_n int;
BEGIN
  SELECT user_id INTO v_admin_user_id FROM telegram_admin WHERE chat_id = p_admin_chat_id AND aktif = true;
  IF v_admin_user_id IS NULL THEN
    RAISE EXCEPTION 'Chat Telegram ini tidak didaftarkan sebagai pemilik atau tidak aktif';
  END IF;
  SELECT EXISTS(SELECT 1 FROM profiles WHERE id = v_admin_user_id AND role = 'pemilik') INTO v_ok;
  IF NOT v_ok THEN
    RAISE EXCEPTION 'Akaun berkaitan bukan pemilik';
  END IF;
  IF p_status NOT IN ('disahkan','ditolak') THEN
    RAISE EXCEPTION 'Status tidak sah: %', p_status;
  END IF;

  IF p_jadual = 'serahan_cash' THEN
    UPDATE serahan_cash SET status = p_status, disahkan_oleh = v_admin_user_id, disahkan_pada = now()
      WHERE id = p_id AND status = 'menunggu';
    IF NOT FOUND THEN RAISE EXCEPTION 'Rekod tidak dijumpai atau sudah diputuskan'; END IF;
    RETURN 'Serahan cash ' || CASE WHEN p_status='disahkan' THEN 'disahkan ✅' ELSE 'ditolak ✕' END;

  ELSIF p_jadual = 'permohonan_cuti' THEN
    UPDATE permohonan_cuti SET status = p_status WHERE id = p_id AND status = 'menunggu';
    IF NOT FOUND THEN RAISE EXCEPTION 'Rekod tidak dijumpai atau sudah diputuskan'; END IF;
    RETURN 'Permohonan cuti/MC/off ' || CASE WHEN p_status='disahkan' THEN 'diluluskan ✅' ELSE 'ditolak ✕' END;

  ELSIF p_jadual = 'permohonan_bayaran_hutang' THEN
    SELECT * INTO v_row FROM permohonan_bayaran_hutang WHERE id = p_id AND status = 'menunggu';
    IF NOT FOUND THEN RAISE EXCEPTION 'Rekod tidak dijumpai atau sudah diputuskan'; END IF;

    IF p_status = 'disahkan' THEN
      IF v_row.kedai_id IS NOT NULL THEN
        IF v_row.settlement_penuh THEN
          UPDATE kedai SET hutang = 0 WHERE id = v_row.kedai_id;
          UPDATE transaksi SET status = 'selesai', jumlah_dibayar = GREATEST(jumlah_dibayar, jumlah)
            WHERE kedai_id = v_row.kedai_id AND status = 'hutang';
        ELSE
          PERFORM agih_bayaran_hutang(v_row.kedai_id, NULL, v_row.jumlah);
        END IF;
      ELSE
        IF v_row.settlement_penuh THEN
          UPDATE transaksi SET status = 'selesai', jumlah_dibayar = GREATEST(jumlah_dibayar, jumlah)
            WHERE kedai_id IS NULL AND nama_pembeli = v_row.nama_pembeli AND status = 'hutang';
        ELSE
          PERFORM agih_bayaran_hutang(NULL, v_row.nama_pembeli, v_row.jumlah);
        END IF;
      END IF;
    END IF;

    UPDATE permohonan_bayaran_hutang SET status = p_status, disahkan_oleh = v_admin_user_id, disahkan_pada = now() WHERE id = p_id;
    RETURN 'Bayaran hutang RM' || v_row.jumlah || ' ' || CASE WHEN p_status='disahkan' THEN 'disahkan ✅' ELSE 'ditolak ✕' END;

  ELSIF p_jadual = 'serahan_produk' THEN
    SELECT * INTO v_row FROM serahan_produk WHERE id = p_id AND status = 'menunggu';
    IF NOT FOUND THEN RAISE EXCEPTION 'Rekod tidak dijumpai atau sudah diputuskan'; END IF;

    IF v_row.jenis = 'ambil' THEN
      IF p_status = 'disahkan' THEN
        UPDATE stok SET stok = stok - v_row.kuantiti WHERE id = v_row.stok_id AND stok >= v_row.kuantiti;
        IF NOT FOUND THEN RAISE EXCEPTION 'Stok gudang tidak mencukupi lagi — mungkin sudah diambil/pindah sejak permohonan dihantar'; END IF;
        INSERT INTO stok_pekerja (pekerja_id, stok_id, kuantiti) VALUES (v_row.pekerja_id, v_row.stok_id, v_row.kuantiti)
          ON CONFLICT (pekerja_id, stok_id) DO UPDATE SET kuantiti = stok_pekerja.kuantiti + v_row.kuantiti;
      END IF;
    ELSIF v_row.jenis IN ('reject','baik') THEN
      IF p_status = 'ditolak' THEN
        INSERT INTO stok_pekerja (pekerja_id, stok_id, kuantiti) VALUES (v_row.pekerja_id, v_row.stok_id, v_row.kuantiti)
          ON CONFLICT (pekerja_id, stok_id) DO UPDATE SET kuantiti = stok_pekerja.kuantiti + v_row.kuantiti;
      ELSIF p_status = 'disahkan' AND v_row.jenis = 'baik' THEN
        UPDATE stok SET stok = stok + v_row.kuantiti WHERE id = v_row.stok_id;
      END IF;
    ELSE
      RAISE EXCEPTION 'Jenis serahan_produk tidak disokong via Telegram: %', v_row.jenis;
    END IF;

    UPDATE serahan_produk SET status = p_status, disahkan_oleh = v_admin_user_id, disahkan_pada = now() WHERE id = p_id;
    RETURN 'Serahan produk (' || v_row.stok_nama || ' ×' || v_row.kuantiti || ') ' || CASE WHEN p_status='disahkan' THEN 'disahkan ✅' ELSE 'ditolak ✕' END;

  ELSIF p_jadual = 'baucar_bayaran' THEN
    IF p_status = 'disahkan' THEN
      UPDATE baucar_bayaran SET status = 'diluluskan', diluluskan_oleh = v_admin_user_id, diluluskan_pada = now()
        WHERE id = p_id AND status = 'draf';
      IF NOT FOUND THEN RAISE EXCEPTION 'Baucar tidak dijumpai atau bukan lagi draf (mungkin sudah diluluskan/dibayar/dibatalkan)'; END IF;
      RETURN 'Baucar harian diluluskan ✅';
    ELSE
      UPDATE baucar_bayaran SET status = 'dibatalkan' WHERE id = p_id AND status = 'draf';
      IF NOT FOUND THEN RAISE EXCEPTION 'Baucar tidak dijumpai atau bukan lagi draf (mungkin sudah diluluskan/dibayar/dibatalkan)'; END IF;
      RETURN 'Baucar harian dibatalkan ✕';
    END IF;

  ELSIF p_jadual = 'affiliates' THEN
    SELECT * INTO v_row FROM affiliates WHERE id = p_id::uuid AND status = 'menunggu';
    IF NOT FOUND THEN RAISE EXCEPTION 'Permohonan tidak dijumpai atau sudah diproses'; END IF;

    IF p_status = 'disahkan' THEN
      -- Jana kod drpd perkataan pertama nama (huruf sahaja, huruf besar); tambah
      -- angka kalau kod tu sudah dipakai affiliate lain.
      v_kod := upper(regexp_replace(split_part(v_row.nama, ' ', 1), '[^A-Za-z]', '', 'g'));
      IF v_kod = '' THEN v_kod := 'AFF'; END IF;
      v_kod_cuba := v_kod;
      v_n := 1;
      WHILE EXISTS (SELECT 1 FROM affiliates WHERE kod_affiliate = v_kod_cuba) LOOP
        v_n := v_n + 1;
        v_kod_cuba := v_kod || v_n;
      END LOOP;
      UPDATE affiliates SET
        kod_affiliate = v_kod_cuba, status = 'aktif',
        disahkan_oleh = v_admin_user_id, disahkan_pada = now()
      WHERE id = p_id::uuid AND status = 'menunggu';
      IF NOT FOUND THEN RAISE EXCEPTION 'Permohonan tidak dijumpai atau sudah diproses'; END IF;
      RETURN 'Affiliate diluluskan ✅ Kod: ' || v_kod_cuba || ' (komisen ' || v_row.kadar_komisen_peratus || '%, diskaun ' || v_row.kadar_diskaun_peratus || '%)';
    ELSE
      UPDATE affiliates SET status = 'ditolak', disahkan_oleh = v_admin_user_id, disahkan_pada = now()
      WHERE id = p_id::uuid AND status = 'menunggu';
      IF NOT FOUND THEN RAISE EXCEPTION 'Permohonan tidak dijumpai atau sudah diproses'; END IF;
      RETURN 'Permohonan affiliate dibatalkan ✕';
    END IF;

  ELSE
    RAISE EXCEPTION 'Jadual tidak disokong via Telegram: %', p_jadual;
  END IF;
END;
$function$;
