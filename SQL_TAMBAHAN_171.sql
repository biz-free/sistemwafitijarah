-- ============================================================
-- SQL TAMBAHAN 171: Mesej baucar harian ke kumpulan WhatsApp Team Sales — dedah JUMLAH SERAHAN sahaja
-- Arahan Amirul 26 Okt 2026: jangan dedahkan sebarang jumlah (upah/makan/minyak/cash/baki dibayar)
-- kecuali jumlah serahan. Mesej kumpulan baucar kini DIBINA SEMULA di pangkalan data daripada rekod
-- baucar (bukan disalin daripada teks kad Telegram), jadi teks tambahan/custom pada kad tak boleh bocor.
--
-- Format baharu (kumpulan WhatsApp):
--   📢 *KELULUSAN PEMILIK — WAFI TIJARAH TRADING*
--   🔔 Baucar Harian
--   👤 <nama pekerja>
--   📅 <DD/MM/YYYY>
--   Jumlah serahan: RMx.xx      (jika baki negatif = pekerja perlu serah)
--   atau "Tiada serahan"        (jika baki 0 / positif — TIADA sebarang jumlah didedah)
--   ➡️ Baucar harian diluluskan ✅ / dibatalkan ✕
--   👤 oleh <pemilik> · <masa>
--
-- Kad Telegram pemilik TIDAK diubah. Jadual lain (cash, hutang, cuti...) TIDAK diubah.
--  A. fungsi baharu teks_baucar_kumpulan()
--  B. rekod_pemakluman_kelulusan (laluan Telegram): untuk baucar_bayaran, teks dibina semula
--  C. pemakluman_keputusan (laluan web): untuk baucar_bayaran guna teks yang sama
-- ============================================================

-- ---------- A ----------
CREATE OR REPLACE FUNCTION public.teks_baucar_kumpulan(p_baucar_id text, p_lulus boolean, p_footer text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_nama text; v_tarikh date; v_baki double precision; v_serah text;
BEGIN
  SELECT pr.nama, b.tarikh, b.baki INTO v_nama, v_tarikh, v_baki
    FROM baucar_bayaran b LEFT JOIN profiles pr ON pr.id = b.pekerja_id
   WHERE b.id = p_baucar_id;
  IF NOT FOUND THEN RETURN NULL; END IF;

  v_serah := CASE WHEN COALESCE(v_baki, 0) < -0.005
                  THEN 'Jumlah serahan: RM' || to_char(-v_baki, 'FM999999990.00')
                  ELSE 'Tiada serahan' END;

  RETURN '📢 *KELULUSAN PEMILIK — WAFI TIJARAH TRADING*' || E'\n\n'
      || '🔔 Baucar Harian' || E'\n'
      || '👤 ' || COALESCE(v_nama, '?') || E'\n'
      || '📅 ' || COALESCE(to_char(v_tarikh, 'DD/MM/YYYY'), '-') || E'\n'
      || v_serah || E'\n\n'
      || '➡️ ' || CASE WHEN p_lulus THEN 'Baucar harian diluluskan ✅' ELSE 'Baucar harian dibatalkan ✕' END
      || COALESCE(E'\n' || NULLIF(p_footer, ''), '');
END;
$function$;
REVOKE ALL ON FUNCTION public.teks_baucar_kumpulan(text, boolean, text) FROM PUBLIC, anon, authenticated;

-- ---------- B ----------
CREATE OR REPLACE FUNCTION public.rekod_pemakluman_kelulusan(p_jadual text, p_id text, p_status text, p_teks text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE v_id bigint; v_footer text; v_baru text;
BEGIN
  -- Baucar harian: bina semula teks (jumlah serahan sahaja); footer "👤 oleh ... · masa" diambil drpd baris terakhir p_teks
  IF p_jadual = 'baucar_bayaran' THEN
    v_footer := substring(p_teks from '[^\n]*$');
    IF v_footer IS NULL OR v_footer NOT LIKE '👤 oleh %' THEN v_footer := ''; END IF;
    v_baru := teks_baucar_kumpulan(p_id, p_status IN ('disahkan', 'diluluskan'), v_footer);
    IF v_baru IS NOT NULL THEN p_teks := v_baru; END IF;
  END IF;

  SELECT id INTO v_id FROM private.pemakluman_kelulusan
   WHERE jadual = p_jadual AND rekod_id = p_id AND dihantar_pada IS NULL AND dicipta > now() - interval '2 minutes'
   ORDER BY id DESC LIMIT 1;
  IF v_id IS NOT NULL THEN
    UPDATE private.pemakluman_kelulusan SET teks = p_teks, status = p_status WHERE id = v_id;
    RETURN;
  END IF;
  IF EXISTS (SELECT 1 FROM private.pemakluman_kelulusan
              WHERE jadual = p_jadual AND rekod_id = p_id AND dicipta > now() - interval '2 minutes') THEN
    RETURN;
  END IF;
  INSERT INTO private.pemakluman_kelulusan (jadual, rekod_id, status, teks) VALUES (p_jadual, p_id, p_status, p_teks);
END;
$function$;

-- ---------- C ----------
-- Hanya bahagian INSERT di hujung diubah (cawangan baucar_bayaran guna teks_baucar_kumpulan); selebihnya SAMA.
CREATE OR REPLACE FUNCTION public.pemakluman_keputusan()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
DECLARE
  v_n jsonb := to_jsonb(NEW);
  v_lulus boolean;
  v_pekerja text;
  v_pemilik text;
  v_tajuk text;
  v_butiran text;
  v_hasil text;
  v_sasaran text;
  v_masa text;
  v_tanda text;
  v_nota text;
  v_teks text;
BEGIN
  IF TG_TABLE_NAME = 'baucar_bayaran' THEN
    IF NOT (OLD.status = 'draf' AND NEW.status IN ('diluluskan','dibatalkan')) THEN RETURN NEW; END IF;
  ELSE
    IF NOT (OLD.status = 'menunggu' AND NEW.status IN ('disahkan','diluluskan','ditolak')) THEN RETURN NEW; END IF;
  END IF;
  v_lulus := NEW.status IN ('disahkan','diluluskan');
  v_tanda := CASE WHEN v_lulus THEN 'ok' ELSE 'ditolak' END;

  SELECT nama INTO v_pekerja FROM profiles WHERE id::text = v_n->>'pekerja_id';
  SELECT nama INTO v_pemilik FROM profiles
   WHERE id::text = COALESCE(auth.uid()::text, v_n->>'disahkan_oleh', v_n->>'diluluskan_oleh', v_n->>'diputuskan_oleh');
  v_nota := NULLIF(v_n->>'nota', '');

  IF TG_TABLE_NAME = 'serahan_cash' THEN
    v_tajuk := 'Serahan Cash';
    v_butiran := 'RM' || to_char((v_n->>'jumlah')::numeric, 'FM999999990.00') || COALESCE(E'\nNota: ' || v_nota, '');
    v_hasil := 'Serahan cash ' || CASE WHEN v_lulus THEN 'disahkan ✅' ELSE 'ditolak ✕' END;

  ELSIF TG_TABLE_NAME = 'permohonan_cuti' THEN
    v_tajuk := COALESCE(v_n->>'jenis', 'Cuti');
    v_butiran := to_char((v_n->>'tarikh_mula')::date, 'DD/MM/YYYY') || ' - ' || to_char((v_n->>'tarikh_tamat')::date, 'DD/MM/YYYY')
      || COALESCE(E'\nNota: ' || v_nota, '');
    v_hasil := 'Permohonan cuti/MC/off ' || CASE WHEN v_lulus THEN 'diluluskan ✅' ELSE 'ditolak ✕' END;

  ELSIF TG_TABLE_NAME = 'permohonan_bayaran_hutang' THEN
    IF v_n->>'kedai_id' IS NOT NULL THEN
      SELECT nama INTO v_sasaran FROM kedai WHERE id = v_n->>'kedai_id';
    END IF;
    v_sasaran := COALESCE(v_sasaran, COALESCE(v_n->>'nama_pembeli', '?') || ' (Peribadi)');
    v_tajuk := 'Bayaran Hutang';
    v_butiran := '🎯 ' || v_sasaran || E'\nRM' || to_char((v_n->>'jumlah')::numeric, 'FM999999990.00')
      || ' (' || COALESCE(v_n->>'kaedah_bayaran', '?') || ')'
      || CASE WHEN (v_n->>'settlement_penuh')::boolean THEN ' · PENUH' ELSE '' END;
    v_hasil := 'Bayaran hutang RM' || to_char((v_n->>'jumlah')::numeric, 'FM999999990.00') || ' ' || CASE WHEN v_lulus THEN 'disahkan ✅' ELSE 'ditolak ✕' END;

  ELSIF TG_TABLE_NAME = 'serahan_produk' THEN
    v_tajuk := CASE v_n->>'jenis'
      WHEN 'ambil' THEN 'Permohonan Ambil Stok'
      WHEN 'baik' THEN 'Serahan Produk (Baik)'
      WHEN 'reject' THEN 'Serahan Produk (Reject)'
      ELSE 'Serahan Produk (' || COALESCE(v_n->>'jenis', '?') || ')' END;
    v_butiran := COALESCE(v_n->>'stok_nama', '?') || ' ×' || COALESCE(v_n->>'kuantiti', '?')
      || COALESCE(E'\nSebab: ' || NULLIF(v_n->>'sebab', ''), '');
    v_hasil := 'Serahan produk (' || COALESCE(v_n->>'stok_nama', '?') || ' ×' || COALESCE(v_n->>'kuantiti', '?') || ') '
      || CASE WHEN v_lulus THEN 'disahkan ✅' ELSE 'ditolak ✕' END;

  ELSIF TG_TABLE_NAME = 'permohonan_padam' THEN
    v_tajuk := 'Permohonan Padam';
    v_butiran := COALESCE(v_n->>'rekod_label', v_n->>'rekod_id', '?') || ' (' || COALESCE(v_n->>'jenis', '?') || ')'
      || COALESCE(E'\nSebab: ' || NULLIF(v_n->>'sebab', ''), '');
    v_hasil := 'Permohonan padam ' || CASE WHEN v_lulus THEN 'diluluskan ✅' ELSE 'ditolak ✕' END;

  ELSIF TG_TABLE_NAME = 'baucar_bayaran' THEN
    v_tajuk := 'Baucar ' || replace(COALESCE(v_n->>'kategori', ''), '_', ' ');
    v_butiran := COALESCE(to_char((v_n->>'tarikh')::date, 'DD/MM/YYYY'), COALESCE(v_n->>'bulan', ''))
      || ' — RM' || to_char(COALESCE((v_n->>'jumlah')::numeric, 0), 'FM999999990.00')
      || COALESCE(E'\n' || NULLIF(v_n->>'tujuan', ''), '');
    v_hasil := 'Baucar ' || CASE WHEN v_lulus THEN 'diluluskan ✅' ELSE 'dibatalkan ✕' END;

  ELSE
    RETURN NEW;
  END IF;

  v_masa := to_char(now() AT TIME ZONE 'Asia/Kuala_Lumpur', 'DD/MM/YY, FMHH12:MI')
    || CASE WHEN extract(hour FROM (now() AT TIME ZONE 'Asia/Kuala_Lumpur')) < 12 THEN ' PG' ELSE ' PTG' END;

  -- Baucar HARIAN sahaja: teks kumpulan dibina semula (jumlah serahan sahaja). Baucar kategori lain: format asal.
  IF TG_TABLE_NAME = 'baucar_bayaran' AND v_n->>'kategori' = 'upah_harian' THEN
    v_teks := teks_baucar_kumpulan(NEW.id::text, v_lulus, '👤 oleh ' || COALESCE(v_pemilik, 'Pemilik') || ' · ' || v_masa);
  END IF;
  IF v_teks IS NULL THEN
    v_teks := '📢 *KELULUSAN PEMILIK — WAFI TIJARAH TRADING*' || E'\n\n'
      || '🔔 ' || v_tajuk || E'\n👤 ' || COALESCE(v_pekerja, '?') || E'\n' || v_butiran
      || E'\n\n➡️ ' || v_hasil || E'\n👤 oleh ' || COALESCE(v_pemilik, 'Pemilik') || ' · ' || v_masa;
  END IF;

  INSERT INTO private.pemakluman_kelulusan (jadual, rekod_id, status, teks)
  VALUES (TG_TABLE_NAME, NEW.id::text, CASE WHEN v_lulus THEN 'disahkan' ELSE 'ditolak' END, v_teks);
  RETURN NEW;
EXCEPTION WHEN others THEN
  RAISE WARNING '[pemakluman_keputusan] gagal utk % %: %', TG_TABLE_NAME, NEW.id, SQLERRM;
  RETURN NEW;
END;
$function$;

-- Pengesahan (SELECT sahaja):
--   select public.teks_baucar_kumpulan('ecc125ba-6714-4c30-9c00-4844c4bb1b91', true, '👤 oleh Contoh · 26/10/26, 10:20 PTG');
--   (fungsi ini REVOKE; jalankan sebagai postgres melalui SQL editor/MCP)
