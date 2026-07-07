# 🌙 Panduan Setup — Wafi Tijarah Trading App

**Syarikat Wafi Tijarah Trading · No. Pendaftaran: AS0462205-D**
Kawasan liputan: Kedah, Perlis, Pulau Pinang & Perak
📞 014-6363831 · ✉️ wafitijarahtrading@gmail.com

> 🚨 **PENTING — jalankan SEGERA jika anda dah jalankan `SQL_TAMBAHAN_2.sql` sebelum ini:** ada bug "infinite recursion" pada dasar `profiles` yang boleh sekat log masuk & urus stok/kedai. Jalankan `SQL_HOTFIX_RECURSION.sql` di SQL Editor SEKARANG untuk baiki (selamat, tak hilang data).
>
> 🆕 **Sudah sambung Supabase sebelum ini?** Jalankan SQL tambahan mengikut turutan (skip yang dah pernah jalankan):
> 1. `SQL_TAMBAHAN_2.sql` — Urus Pekerja & Link Pre-Order
> 2. `SQL_HOTFIX_RECURSION.sql` — **wajib** selepas #1 (baiki bug di atas)
> 3. `SQL_TAMBAHAN_3.sql` — Reset Kata Laluan, Thumb In/Out & Jejak GPS (perlu deploy Edge Function juga — lihat bahagian "Reset Kata Laluan Pekerja" di bawah)
>
> Tak perlu jalankan `SETUP_SQL_LENGKAP.sql` semula jika projek Supabase anda dah aktif (fail itu sudah dikemas kini dengan pembetulan yang sama untuk pemasangan BAHARU).

## 📱 Cara Install Apps ke Phone (APK / PWA)

### Langkah 1 — Host apps (percuma)

**Pilihan A: GitHub Pages (Disyorkan, 100% Percuma)**
1. Daftar akaun di github.com
2. Klik "New Repository" → nama: `wafi-app`
3. Upload semua fail (index.html, manifest.json, sw.js, icon-192.png, icon-512.png)
4. Pergi Settings → Pages → Source: main branch
5. URL apps anda: `https://[username].github.io/wafi-app`

**Pilihan B: Netlify (Lebih Mudah)**
1. Pergi netlify.com → "Deploy manually"
2. Drag & drop folder `wafi-app`
3. URL terus jadi: `https://wafi-tijarah.netlify.app`

---

### Langkah 2 — Install ke Phone Android

1. Buka URL apps dalam **Chrome** (wajib Chrome)
2. Tunggu 30 saat dalam apps
3. Chrome akan tunjuk banner "Add to Home screen"
4. ATAU tekan menu ⋮ → "Add to Home screen"
5. Tekan "Add" → ikon apps muncul kat homescreen
6. **Selesai! Rasa macam apps sebenar** — apps juga boleh dibuka semasa offline (service worker cache app shell secara automatik)

### Install ke iPhone (iOS)

1. Buka URL dalam **Safari** (wajib Safari)
2. Tekan ikon Share (kotak dengan anak panah atas)
3. Scroll ke bawah → "Add to Home Screen"
4. Tekan "Add"

---

## ✨ Ciri-Ciri Sistem

### 📍 Lokasi Kedai — Peta Pin Picker
Bila daftar/edit kedai, taip alamat dalam kotak carian dan tekan "Cari" — pin akan bergerak terus ke lokasi tersebut, atau klik/seret pin terus di peta. Guna **OpenStreetMap + Nominatim** (100% percuma, tiada API key/kad kredit diperlukan langsung, berbeza dengan Google Maps). Koordinat tersimpan automatik — tiada isian manual latitud/longitud diperlukan lagi.

### ⏳ Stok Luput & Tukar Stok
Setiap produk boleh ada 1 tarikh luput (dikemaskini semasa restock). Sistem beri amaran di Dashboard & Stok bila produk luput dalam masa 30 hari atau sudah luput. Bila stok sudah luput, pemilik boleh tekan **"🔁 Tukar Stok Luput"** untuk rekod kuantiti dibuang & kuantiti gantian baru diterima (biasanya percuma daripada pembekal) sekaligus kemaskini tarikh luput baru.

### 💰 Kos Operasi & Untung Bersih
Laporan Bulanan kini kira **untung bersih sebenar**, bukan sekadar untung kasar:
- Upah Pekerja: RM per stok dihantar (lalai RM1.00)
- Minyak Kenderaan: RM per km (lalai RM0.50) — diisi semasa rekod penghantaran
- Duit Makan: RM sehari seorang pekerja (lalai RM10.00) — dikira ikut hari sebenar pekerja buat penghantaran

Kadar ini boleh diedit oleh pemilik di **Lagi → Tetapan Kos Operasi**. Nilai modal (harga beli) dan margin keuntungan **tidak dipaparkan** kepada akaun pekerja — hanya pemilik nampak.

> ⚠️ Nota: Tetapan kos operasi ini disimpan setakat ini secara tempatan (localStorage) di setiap peranti, walaupun selepas Supabase disambung. Jika anda mahu kadar ini sentiasa sama merentasi semua peranti pemilik, minta pembangun tambah jadual `settings` di Supabase.

### 🧾 Resit — PDF & WhatsApp
Selain cetak biasa, ada 2 butang tambahan di halaman Lagi:
- **📄 Muat Turun PDF** — jana fail PDF resit terus ke peranti.
- **📱 Hantar Resit via WhatsApp** — buka WhatsApp terus ke no. telefon kedai dengan mesej ringkasan resit siap ditaip.

> ⚠️ **Had penting**: Aplikasi web percuma **tidak boleh melampirkan fail PDF secara automatik** ke dalam mesej WhatsApp (had platform WhatsApp, bukan had sistem ini). Bila tekan butang WhatsApp, PDF akan dimuat turun serta-merta DAN WhatsApp akan terbuka dengan mesej siap ditaip — pekerja perlu **lekatkan (attach) fail PDF tersebut secara manual** dalam WhatsApp (2 langkah je). Hantar automatik sepenuhnya tanpa campur tangan hanya boleh dicapai melalui WhatsApp Business API rasmi (perlu pendaftaran Meta Business, verifikasi syarikat & bayaran bulanan/per-mesej) — berbeza projek berasingan jika diperlukan kelak.

Resit juga papar **no. telefon pekerja** yang buat penghantaran tersebut (jika direkod semasa daftar pekerja), supaya kedai boleh terus hubungi pekerja itu untuk repeat order tanpa perlu apps.

### 🔑 Lupa Kata Laluan
Kedua-dua pemilik & pekerja boleh tekan "Lupa kata laluan?" di skrin log masuk, masukkan e-mel, dan pautan reset akan dihantar terus oleh Supabase. Ciri ini **hanya berfungsi dalam mod cloud** (selepas Supabase disambung).

### 🔑 Reset Kata Laluan Pekerja ke "admin123" (Pemilik sahaja)
Di **Lagi → Urus Pekerja**, pemilik boleh tekan **"🔑 Reset admin123"** pada mana-mana pekerja yang lupa kata laluan. Pekerja tersebut akan diminta **tetapkan kata laluan baharu** (tak boleh admin123 semula) sebelum boleh masuk ke ruang utama pada log masuk seterusnya.

> ⚠️ **Kenapa hanya pemilik boleh buat ini (bukan sesiapa dari skrin log masuk)?** Jika sesiapa boleh reset password akaun lain ke nilai tetap (admin123) hanya dengan tahu e-mel — itu jadi lubang keselamatan (curi akaun). Sebab itu tindakan ini perlu pengesahan pemilik yang sudah log masuk, dan dijalankan melalui **Edge Function** (kod pelayan berasingan yang pegang kunci admin Supabase secara selamat — kunci ini TIDAK PERNAH masuk ke dalam kod `index.html` yang orang ramai boleh lihat).

**Deploy Edge Function (buat SEKALI sahaja):**
1. Pastikan Node.js dipasang di komputer anda (untuk `npx`)
2. Buka Command Prompt/Terminal, masuk ke folder `wafi-app` yang ada folder `supabase/functions/reset-pekerja-password/`
3. Log masuk CLI Supabase (buka pelayar untuk sahkan):
   ```
   npx supabase login
   ```
4. Pautkan ke project anda:
   ```
   npx supabase link --project-ref smepriytkoxkmpvjvvzq
   ```
5. Deploy fungsi:
   ```
   npx supabase functions deploy reset-pekerja-password
   ```
6. Selesai — butang "Reset admin123" dalam apps akan berfungsi selepas ini.

### 👍👎 Thumb In / Thumb Out (Kehadiran Pekerja)
Di Dashboard, pekerja tekan **"👍 Thumb In"** untuk mula kerja dan **"👎 Thumb Out"** untuk tamat kerja. Setiap kali, telefon akan minta pengesahan **fingerprint/Face ID sedia ada di telefon tersebut** (WebAuthn) — kali pertama guna, pekerja akan diminta daftar fingerprint/Face ID dahulu (sekali sahaja per peranti).

> ⚠️ **Had sebenar**: Website **tidak boleh** mengimbas cap ibu jari terus seperti mesin kehadiran pejabat — ia guna ciri fingerprint/Face ID yang SEDIA ADA pada telefon pekerja untuk sahkan identiti (standard moden, selamat). Pengesahan ini disahkan di peringkat **peranti/pelayar** sahaja dalam versi ini (bukan disahkan semula secara kriptografi di server) — memadai untuk rekod kehadiran dalaman, tapi jika perlukan tahap lebih tegas (contoh untuk tujuan audit rasmi), boleh ditambah baik lagi dengan Edge Function tambahan pada masa depan.

### 📍 Jejak GPS & Anggaran Jarak (Claim Minyak)
Bermula dari Thumb In sehingga Thumb Out, lokasi GPS pekerja direkod **setiap 30 minit**, ditambah titik lokasi semasa Thumb In & Thumb Out sendiri. Pemilik boleh lihat anggaran jarak (km) dan kos minyak setiap sesi kerja di **Lagi → Kehadiran & Jarak Pekerja** (pilih tarikh).

> ⚠️ **Had sebenar GPS web app**: Penjejakan ini **hanya berfungsi selagi apps dibuka** (tab/PWA di latar depan). Ia BUKAN apps GPS khusus seperti Grab Driver — bila skrin telefon dikunci lama atau apps ditutup, penjejakan terhenti sehingga apps dibuka semula. Ini adalah had platform web (bukan boleh diperbaiki tanpa jadi apps mudah alih asli/native). Anggaran jarak dikira dari titik-ke-titik (garis lurus), bukan jarak jalan sebenar — sesuai sebagai rujukan kasar untuk claim, bukan ukuran GPS profesional.

### 👥 Urus Pekerja (Daftar Terus Dalam Apps)
Pemilik boleh daftar akaun pekerja baru terus dari **Lagi → Urus Pekerja** (nama, e-mel, no. telefon, kata laluan sementara) tanpa perlu masuk dashboard Supabase setiap kali. Sistem guna sambungan sementara (session berasingan) supaya sesi log masuk pemilik sendiri tidak terjejas semasa proses ini.

> ⚠️ Jika akaun pekerja baru tak boleh log masuk serta-merta ("Email not confirmed"), pergi ke Supabase → **Authentication → Providers → Email** dan matikan "Confirm email" — supaya akaun terus aktif sebaik didaftarkan tanpa perlu sahkan e-mel.

### 🔗 Link Pre-Order untuk Kedai (Repeat Order)
Satu link awam **`pesan.html`** (cth: `https://biz-free.github.io/sistemwafitijarah/pesan.html`) boleh dikongsi terus dengan mana-mana kedai — mereka boleh isi nama kedai, no. telefon, pilih barang & kuantiti, hantar, TANPA perlu log masuk. Pesanan masuk terus ke tab **Hantar → Pre-Order** dalam apps (nampak oleh pemilik & pekerja) untuk diproses jadi penghantaran sebenar. Link penuh disalin terus dari tab tersebut (butang "📋 Salin").

---

## ☁️ Setup Supabase (Database Cloud)

### Kenapa Supabase?
- **Percuma** sehingga 50,000 baris & 2GB
- Data selamat di cloud Singapore
- Semua pekerja guna data yang sama (sync sebenar antara peranti)

> ⚠️ **Sebelum ini disambung**, aplikasi berjalan dalam "Mod Tempatan" — data hanya disimpan dalam peranti (localStorage) dan kata laluan awal boleh dilihat sesiapa yang buka "View Source". Ikut langkah di bawah untuk sambung Supabase supaya data sebenar & kata laluan pekerja betul-betul selamat.

### Langkah Setup:

**1. Buat akaun**
- Pergi ke supabase.com
- Klik "Start your project"
- Log masuk dengan Google

**2. Buat project**
- Nama: `wafi-tijarah`
- Password database: (tetapkan sendiri, simpan elok-elok)
- Region: Southeast Asia (Singapore)
- Tunggu ~2 minit

**3. Jalankan SQL ini**
- Dalam dashboard Supabase, klik "SQL Editor"
- Copy-paste SQL di bawah, klik "Run"

```sql
-- ═══ Jadual data ═══
CREATE TABLE stok (
  id text PRIMARY KEY,
  nama text NOT NULL,
  unit text DEFAULT 'unit',
  harga_beli float DEFAULT 0,
  harga_jual float DEFAULT 0,
  stok int DEFAULT 0,
  kategori text DEFAULT 'Minuman',
  tarikh_luput date,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE kedai (
  id text PRIMARY KEY,
  nama text NOT NULL,
  alamat text,
  negeri text,
  daerah text,
  telefon text,
  lat float DEFAULT 5.15,
  lng float DEFAULT 100.85,
  status text DEFAULT 'aktif',
  hutang float DEFAULT 0,
  nota text,
  last_visit text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE transaksi (
  id text PRIMARY KEY,
  tarikh_masa timestamptz DEFAULT now(),
  kedai_id text REFERENCES kedai(id),
  items jsonb DEFAULT '[]',
  jumlah float DEFAULT 0,
  status text DEFAULT 'selesai',
  nota text,
  resit text,
  jarak_km float DEFAULT 0,
  created_by text
);

-- Profil pekerja/pemilik — dipautkan ke akaun Supabase Auth (Langkah 5)
CREATE TABLE profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email text,
  role text NOT NULL DEFAULT 'pekerja',
  nama text
);

-- ═══ Row Level Security ═══
ALTER TABLE stok ENABLE ROW LEVEL SECURITY;
ALTER TABLE kedai ENABLE ROW LEVEL SECURITY;
ALTER TABLE transaksi ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- Setiap pengguna hanya boleh baca profil sendiri (untuk tentukan peranan lepas log masuk)
CREATE POLICY "profil sendiri" ON profiles FOR SELECT USING (auth.uid() = id);

-- Sesiapa yang log masuk (pemilik/pekerja) boleh baca stok/kedai/transaksi
CREATE POLICY "baca stok" ON stok FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "baca kedai" ON kedai FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "baca transaksi" ON transaksi FOR SELECT USING (auth.role() = 'authenticated');

-- Hanya pemilik boleh tambah/kemaskini produk & kedai terus (pekerja guna fungsi RPC di bawah)
CREATE POLICY "pemilik tambah stok" ON stok FOR INSERT WITH CHECK (
  EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'pemilik')
);
CREATE POLICY "pemilik kemaskini stok" ON stok FOR UPDATE USING (
  EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'pemilik')
);
CREATE POLICY "pemilik tambah kedai" ON kedai FOR INSERT WITH CHECK (
  EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'pemilik')
);
CREATE POLICY "pemilik kemaskini kedai" ON kedai FOR UPDATE USING (
  EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'pemilik')
);

-- ═══ Fungsi RPC — kemaskini stok/hutang secara atomik ═══
-- (Elak "lost update" bila 2 pekerja hantar barang / restock serentak dari 2 telefon)

CREATE OR REPLACE FUNCTION submit_penghantaran(
  p_id text, p_kedai_id text, p_items jsonb, p_jumlah float,
  p_status text, p_nota text, p_resit text, p_jarak_km float DEFAULT 0
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE item jsonb;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid()) THEN
    RAISE EXCEPTION 'Tidak dibenarkan';
  END IF;

  FOR item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    UPDATE stok SET stok = stok - (item->>'qty')::int WHERE id = item->>'stokId';
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Produk % tidak wujud', item->>'stokId';
    END IF;
  END LOOP;

  IF EXISTS (
    SELECT 1 FROM stok s JOIN jsonb_array_elements(p_items) i ON s.id = i->>'stokId' WHERE s.stok < 0
  ) THEN
    RAISE EXCEPTION 'Stok tidak mencukupi untuk salah satu produk';
  END IF;

  INSERT INTO transaksi (id, kedai_id, items, jumlah, status, nota, resit, jarak_km, created_by)
  VALUES (p_id, p_kedai_id, p_items, p_jumlah, p_status, p_nota, p_resit, p_jarak_km, auth.uid()::text);

  UPDATE kedai SET
    hutang = hutang + (CASE WHEN p_status = 'hutang' THEN p_jumlah ELSE 0 END),
    last_visit = CURRENT_DATE::text
  WHERE id = p_kedai_id;
END;
$$;

CREATE OR REPLACE FUNCTION restock_produk(p_id text, p_qty int) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'pemilik') THEN
    RAISE EXCEPTION 'Hanya pemilik boleh restock';
  END IF;
  UPDATE stok SET stok = stok + p_qty WHERE id = p_id;
END;
$$;

CREATE OR REPLACE FUNCTION rekod_bayaran(p_kedai_id text, p_jumlah float) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE baki float := p_jumlah; t RECORD;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'pemilik') THEN
    RAISE EXCEPTION 'Hanya pemilik boleh rekod bayaran';
  END IF;
  UPDATE kedai SET hutang = GREATEST(0, hutang - p_jumlah) WHERE id = p_kedai_id;
  FOR t IN
    SELECT id, jumlah FROM transaksi
    WHERE kedai_id = p_kedai_id AND status = 'hutang'
    ORDER BY tarikh_masa ASC
  LOOP
    EXIT WHEN baki < t.jumlah;
    UPDATE transaksi SET status = 'selesai' WHERE id = t.id;
    baki := baki - t.jumlah;
  END LOOP;
END;
$$;
```

> 💡 Jika Supabase anda sudah dijalankan dengan SQL versi lama (tiada `negeri`, `tarikh_luput`, `jarak_km`), jalankan sahaja SQL tambahan ini untuk kemaskini tanpa kehilangan data sedia ada:
> ```sql
> ALTER TABLE kedai ADD COLUMN IF NOT EXISTS negeri text;
> ALTER TABLE stok ADD COLUMN IF NOT EXISTS tarikh_luput date;
> ALTER TABLE transaksi ADD COLUMN IF NOT EXISTS jarak_km float DEFAULT 0;
> ```
> ...kemudian jalankan semula blok `CREATE OR REPLACE FUNCTION submit_penghantaran(...)` di atas untuk kemaskini fungsi RPC.

**4. Cipta akaun log masuk sebenar**
- Dalam dashboard Supabase, pergi ke **Authentication → Users**
- Klik "Add user" → masukkan e-mel & kata laluan sebenar untuk pemilik
- Ulang untuk setiap pekerja penghantar
- Klik pada setiap pengguna untuk salin **User UID** dia
- Pergi ke **Table Editor → profiles**, tambah baris untuk setiap pengguna:
  - `id` = User UID yang disalin tadi
  - `email` = e-mel pengguna
  - `role` = `pemilik` (untuk 1 akaun) atau `pekerja` (untuk penghantar)
  - `nama` = nama paparan

**5. Salin credentials**
- Pergi Settings → API
- Salin **Project URL** (contoh: https://xxxx.supabase.co)
- Salin **anon/public key** (panjang, bermula dengan eyJ...)

**6. Masukkan dalam apps**
- Buka fail `index.html`
- Cari baris ini (dekat permulaan `<script>`):
```javascript
const SUPABASE_URL = 'YOUR_SUPABASE_URL';
const SUPABASE_KEY = 'YOUR_SUPABASE_ANON_KEY';
```
- Ganti dengan URL dan key anda
- Upload semula ke GitHub/Netlify

> ⚠️ Sebaik sahaja `SUPABASE_URL`/`SUPABASE_KEY` diisi, aplikasi automatik beralih ke mod cloud. Akaun awal (pemilik@wafi.com dll.) **tak lagi berfungsi** — log masuk guna akaun yang dicipta di Langkah 4.

---

## 👥 Akaun Log Masuk

### Mod Tempatan (belum sambung Supabase)

| Nama | E-mel | Kata Laluan | Peranan |
|------|-------|-------------|---------|
| Pemilik | pemilik@wafi.com | wafi2024 | Pemilik (akses penuh) |
| Penghantar 1 | pekerja1@wafi.com | hantar123 | Pekerja (hantar sahaja) |
| Penghantar 2 | pekerja2@wafi.com | hantar456 | Pekerja (hantar sahaja) |

> ⚠️ **Kata laluan awal ini tertanam dalam kod sumber** dan boleh dilihat sesiapa sahaja melalui "View Source" bila apps di-host secara terbuka (GitHub Pages/Netlify). Jangan guna mod tempatan untuk data perniagaan sebenar — sambung Supabase (di atas) supaya kata laluan diuruskan Supabase Auth dan tidak terdedah.

### Mod Cloud (selepas sambung Supabase)

Log masuk guna e-mel & kata laluan yang anda cipta sendiri di **Authentication → Users** (Langkah 4 di atas). Tiada kata laluan lalai — setiap akaun ditetapkan oleh pemilik sistem.

---

## 📊 Perbezaan Akses

| Fungsi | Pemilik 👑 | Pekerja 🚚 |
|--------|------------|------------|
| Dashboard | ✅ | ✅ |
| Lihat Stok (harga jual & baki) | ✅ | ✅ |
| Lihat Nilai Modal / Margin | ✅ | ❌ |
| Tambah/Edit Stok | ✅ | ❌ |
| Restock / Tukar Stok Luput | ✅ | ❌ |
| Lihat Kedai | ✅ | ✅ |
| Tambah/Edit Kedai | ✅ | ❌ |
| Rekod Penghantaran | ✅ | ✅ |
| Terima Bayaran | ✅ | ❌ |
| Jana Resit / PDF / WhatsApp | ✅ | ✅ |
| Laporan Kewangan & Untung Bersih | ✅ | ❌ |
| Tetapan Kos Operasi | ✅ | ❌ |
| Urus Pekerja & Reset Kata Laluan | ✅ | ❌ |
| Thumb In/Out & Jejak GPS Sendiri | ✅ | ✅ |
| Lihat Kehadiran & Jarak Semua Pekerja | ✅ | ❌ |

Dalam mod cloud, sekatan ini dikuatkuasakan **dua lapis**: paparan UI (client) DAN dasar RLS/fungsi RPC di pangkalan data (server) — jadi walaupun pekerja cuba panggil fungsi terus dari console browser, sekatan peranan tetap terpakai.

---

## 🔧 Sokongan Teknikal

Jika ada masalah, hubungi pembangun sistem atau rujuk:
- Supabase Docs: docs.supabase.com
- PWA Guide: web.dev/progressive-web-apps
- OpenStreetMap/Nominatim Usage Policy: operations.osmfoundation.org/policies/nominatim (guna sederhana sahaja, elak carian berlebihan dalam masa singkat)

---

**Wafi Tijarah Trading · No. Pendaftaran: AS0462205-D**
**Sistem Pengurusan Penghantaran v2.0**
*Produk Halal · Berkualiti · Amanah*
*Kedah · Perlis · Pulau Pinang · Perak*
