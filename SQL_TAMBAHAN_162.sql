-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 162: Kelulusan bayaran hutang melalui Telegram turut kumpul bayaran
-- separa pada invois (sambungan SQL 159).
--
-- PUNCA: SQL 159 membaiki rekod_bayaran() (web) supaya bayaran separa dikumpul pada
-- invois (jumlah_dibayar). TETAPI telegram_putuskan() (butang ✅ Telegram utk
-- permohonan_bayaran_hutang) ada logik agihan SENDIRI yang masih lama — hanya tanda
-- invois 'selesai' jika SATU bayaran menampung penuh jumlahnya. Kes seperti Pasaraya
-- Arisya (hutang kedai RM0 tapi invois kekal 'hutang') masih boleh berulang bila
-- bayaran separa diluluskan dari Telegram.
--
-- PENYELESAIAN: fungsi dalaman agih_bayaran_hutang() (logik sama spt rekod_bayaran
-- SQL 159, tanpa semakan auth.uid() kerana Telegram guna service_role; HANYA
-- service_role boleh panggil) dan telegram_putuskan() kini memanggilnya. Cabang
-- settlement_penuh turut set jumlah_dibayar. Cabang lain TIDAK diubah.
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.agih_bayaran_hutang(p_kedai_id text, p_nama_pembeli text, p_jumlah double precision)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE baki float := p_jumlah; t RECORD; bayar float; hutang_baru float;
BEGIN
  IF p_jumlah IS NULL OR p_jumlah <= 0 THEN RAISE EXCEPTION 'Jumlah bayaran mesti lebih 0'; END IF;

  IF p_kedai_id IS NOT NULL THEN
    UPDATE kedai SET hutang = GREATEST(0, hutang - p_jumlah) WHERE id = p_kedai_id
      RETURNING hutang INTO hutang_baru;
  END IF;

  FOR t IN
    SELECT id, jumlah, jumlah_dibayar FROM transaksi
    WHERE status = 'hutang'
      AND CASE WHEN p_kedai_id IS NOT NULL THEN kedai_id = p_kedai_id
               ELSE kedai_id IS NULL AND nama_pembeli = p_nama_pembeli END
    ORDER BY tarikh_masa ASC
    FOR UPDATE
  LOOP
    EXIT WHEN baki <= 0.005;
    bayar := LEAST(baki, GREATEST(t.jumlah - t.jumlah_dibayar, 0));
    UPDATE transaksi SET
      jumlah_dibayar = jumlah_dibayar + bayar,
      status = CASE WHEN jumlah_dibayar + bayar >= jumlah - 0.005 THEN 'selesai' ELSE status END
    WHERE id = t.id;
    baki := baki - bayar;
  END LOOP;

  IF p_kedai_id IS NOT NULL AND COALESCE(hutang_baru, 1) <= 0.005 THEN
    UPDATE transaksi SET status = 'selesai', jumlah_dibayar = GREATEST(jumlah_dibayar, jumlah)
    WHERE kedai_id = p_kedai_id AND status = 'hutang';
  END IF;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.agih_bayaran_hutang(text, text, double precision) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.agih_bayaran_hutang(text, text, double precision) TO service_role;

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

  ELSE
    RAISE EXCEPTION 'Jadual tidak disokong via Telegram: %', p_jadual;
  END IF;
END;
$function$;
