# 🌙 Panduan Setup — Wafi Tijarah Trading App

**Syarikat Wafi Tijarah Trading · No. Pendaftaran: AS0462205-D**
Kawasan liputan: Kedah, Perlis, Pulau Pinang & Perak
📞 014-6363831 · ✉️ wafitijarahtrading@gmail.com

> 🗂️ **Struktur fail:** `index.html` kini ialah **laman e-dagang runcit** (halaman utama di `www.wafitijarahtrading.com`). Sistem pengurusan penghantaran (log masuk pemilik/pekerja) di fail **`pengurusan.html`**, boleh dicapai melalui pautan "🔐 Log Masuk Pekerja/Pemilik" di bahagian bawah laman utama, atau terus di `www.wafitijarahtrading.com/pengurusan.html`. Borang repeat-order khas kedai runcit (B2B) kekal berasingan di **`pesan.html`**.

> 🚨 **PENTING — jalankan SEGERA jika anda dah jalankan `SQL_TAMBAHAN_2.sql` sebelum ini:** ada bug "infinite recursion" pada dasar `profiles` yang boleh sekat log masuk & urus stok/kedai. Jalankan `SQL_HOTFIX_RECURSION.sql` di SQL Editor SEKARANG untuk baiki (selamat, tak hilang data).
>
> 🆕 **Sudah sambung Supabase sebelum ini?** Jalankan SQL tambahan mengikut turutan (skip yang dah pernah jalankan):
> 1. `SQL_TAMBAHAN_2.sql` — Urus Pekerja & Link Pre-Order
> 2. `SQL_HOTFIX_RECURSION.sql` — **wajib** selepas #1 (baiki bug di atas)
> 3. `SQL_TAMBAHAN_3.sql` — Reset Kata Laluan, Thumb In/Out & Jejak GPS (perlu deploy Edge Function juga — lihat bahagian "Reset Kata Laluan Pekerja" di bawah)
> 4. `SQL_TAMBAHAN_4.sql` — Gambar produk, QR Pre-Order pada resit & diskaun Online Transfer (perlu cipta Storage bucket `produk-gambar` dahulu)
> 5. `SQL_TAMBAHAN_5.sql` — Stok ikut pekerja, tugasan pre-order, cuti/status pekerja, profil sendiri, bukti bayaran transfer (perlu cipta Storage bucket `bukti-bayaran` dahulu — **Public bucket: OFF**, data sensitif)
> 6. `SQL_TAMBAHAN_6.sql` — Baiki ralat "row violates RLS" pada Mohon Cuti & isu claim pre-order salah
> 7. `SQL_TAMBAHAN_7.sql` — Tempoh tugasan pre-order (auto-pulang lepas 1 hari), padam data, gambar berbilang, tugaskan pekerja oleh pemilik
> 8. `SQL_TAMBAHAN_8.sql` — Alamat & lokasi GPS pada pre-order (pembeli cari lokasi kedai sendiri di borang awam)
> 9. `SQL_TAMBAHAN_9.sql` — Belian peribadi (tiada kedai), upah pekerja per-produk, status pekerja tidak aktif (boleh dipadam)
> 10. `SQL_TAMBAHAN_10.sql` — Baiki padam kedai (409 jika ada sejarah), diskaun COD/Transfer berasingan, had Consignment
> 11. `SQL_TAMBAHAN_11.sql` — Fasa 1 Laman E-Dagang (`index.html`): zon penghantaran, jadual pesanan e-dagang
> 12. `SQL_TAMBAHAN_12.sql` — **Wajib** untuk checkout e-dagang berfungsi: baiki bukti bayaran & tarikh/masa transfer yang belum disimpan
> 13. `SQL_TAMBAHAN_13.sql` — Sambungan OAuth EasyParcel (Fasa 3a) — lihat bahagian "🚚 Sambung EasyParcel" di bawah untuk setup Edge Function
> 14. `SQL_TAMBAHAN_14.sql` — Kadar penghantaran sebenar & label EasyParcel (Fasa 3b) — perlu deploy 2 Edge Function baru, lihat bahagian "🚚 Kadar Sebenar & Label EasyParcel" di bawah
> 15. `SQL_TAMBAHAN_15.sql` — **Wajib** selepas #14: simpan pautan cetak label & jejak tracking selepas label EasyParcel dijana — perlu redeploy `easyparcel-book-shipment` (baiki bug URL endpoint salah)
> 16. `SQL_TAMBAHAN_16.sql` — Bayaran Online Billplz (Fasa 2) — perlu deploy 2 Edge Function baru, lihat bahagian "💳 Bayaran Online (Billplz)" di bawah untuk setup akaun & secrets
> 17. `SQL_TAMBAHAN_17.sql` — 🚨 **KESELAMATAN, WAJIB SEGERA**: baiki celah di mana sesiapa boleh hantar harga produk/status bayaran palsu terus ke pangkalan data (lihat bahagian "🚨 Keselamatan" di bawah)
> 18. `SQL_TAMBAHAN_18.sql` — 🚨 **KESELAMATAN**: celah yang sama untuk borang repeat-order kedai (`pesan.html`) — kira semula jumlah & had consignment daripada tetapan sebenar
> 19. `SQL_TAMBAHAN_19.sql` — Simpan bandar (city) pelanggan, diisi automatik daripada poskod semasa checkout — perlu redeploy `easyparcel-book-shipment` (guna bandar sebenar untuk label, bukan nama negeri)
> 20. `SQL_TAMBAHAN_20.sql` — Penghantaran percuma `pesan.html` (minima RM100, boleh ubah) + jadual permohonan Ejen & Penghantar Part-Time
> 21. `SQL_TAMBAHAN_21.sql` — Kunci peranti GPS semasa Thumb In (elak 2 peranti hantar GPS serentak) + kaedah bayaran "Online Transfer" & diskaun % di Rekod Baru — lihat bahagian "📡 Kunci Peranti GPS" & "💳 Kaedah Bayaran di Rekod Baru" di bawah
> 22. `SQL_TAMBAHAN_22.sql` — Rekod siapa daftarkan setiap kedai (untuk bonus "Kedai Baru" & paparan di Senarai Kedai) — lihat bahagian "🏪 Bonus Kedai Baru" di bawah
> 23. `SQL_TAMBAHAN_23.sql` — Pelupusan Stok (rosak/expired/hilang) direkod terus dari tab Penghantaran — lihat bahagian "🗑️ Pelupusan Stok" di bawah
> 24. `SQL_TAMBAHAN_24.sql` — Pemilik tugaskan pekerja untuk urus setiap pesanan e-dagang; pekerja tak ditugaskan tak nampak pesanan itu langsung — lihat bahagian "🛒 Tugasan Pesanan E-Dagang" di bawah
> 26. `SQL_TAMBAHAN_26.sql` — Galeri gambar kedai + Baucar Bayaran (Payment Voucher) bernombor siri untuk audit LHDN — lihat bahagian "📸 Galeri Gambar Kedai" & "🧾 Baucar Bayaran" di bawah. **Perlu cipta 2 bucket Storage baharu secara manual dahulu** (`kedai-gambar` — Public ON, `baucar-resit` — Public OFF), lihat arahan dalam fail SQL.
> 27. `SQL_TAMBAHAN_27.sql` — Tambah lajur `butiran` pada `baucar_bayaran` untuk baucar Petrol menyimpan log perjalanan harian (tarikh + km) sebagai bukti sokongan automatik — lihat bahagian "🧾 Baucar Bayaran" di bawah. Tiada bucket Storage baharu diperlukan.
> 28. `SQL_TAMBAHAN_28.sql` — Consignment: upah pekerja untuk penghantaran consignment kini hanya dikira SELEPAS kedai sahkan jualan sebenar (sokong jualan separa) — lihat bahagian "🤝 Consignment — Upah Ikut Jualan Sebenar" di bawah. Tiada bucket Storage baharu diperlukan.
> 29. `SQL_TAMBAHAN_29.sql` — Voucher Diskaun untuk storefront B2C (index.html) — pemilik jana kod diskaun (peratus/tetap), pelanggan claim semasa checkout — lihat bahagian "🎟️ Voucher Diskaun" di bawah. Tiada bucket Storage baharu diperlukan.
> 30. `SQL_TAMBAHAN_30.sql` — Pembetulan bug: padam transaksi kedai kini pulangkan stok ke gudang pusat & laraskan balik hutang kedai (dulu stok "hilang" apabila transaksi dipadam). Tiada bucket Storage baharu diperlukan.
> 31. `SQL_TAMBAHAN_31.sql` — "Sertai Ejen" digantikan dengan "Sertai Kami — Servis Marketing" (borang pembekal produk) — lihat bahagian "📦 Sertai Kami — Servis Marketing" di bawah. Tiada bucket Storage baharu diperlukan (guna semula bucket `produk-gambar`).
> 32. `SQL_TAMBAHAN_32.sql` — Route/Laluan Kedai (tab Kedai → Perlu Servis) + Kategori Produk boleh edit (tab Stok) — lihat bahagian "🗺️ Route/Laluan Kedai" & "🏷️ Kategori Produk Boleh Edit" di bawah. Tiada bucket Storage baharu diperlukan.
> 33. Deploy Edge Function baharu `produk-preview` — preview WhatsApp/Facebook untuk pautan produk dikongsi — lihat bahagian "📱 Preview WhatsApp untuk Pautan Produk" di bawah. Tiada perubahan SQL diperlukan.
> 34. `SQL_TAMBAHAN_33.sql` — pesan.html: kategori produk, susun semula 2-halaman & kaedah "💳 Bayar Online" (Billplz) — lihat bahagian "🛍️ Kemaskini Borang Pesan (pesan.html)" di bawah. **Perlu deploy semula `billplz-create-bill` & `billplz-webhook`.**
> 35. `SQL_TAMBAHAN_34.sql` — Ikon "📦 Jejak Pesanan" di header index.html, pelanggan masukkan nombor pesanan untuk semak status & tracking kurier — lihat bahagian "📦 Jejak Pesanan" di bawah. Tiada bucket Storage/Edge Function baharu diperlukan.
> 36. Deploy Edge Function baharu `easyparcel-track-order` — status kurier LIVE (on-demand) dalam modal "📦 Jejak Pesanan" bila pembeli tekan butang "🔍 Jejak" — lihat bahagian "📦 Jejak Pesanan" di bawah (kemaskini). Tiada perubahan SQL diperlukan.
> 37. Deploy Edge Function baharu `produk-preview-gen` + set secret `GITHUB_TOKEN` — pratonton WhatsApp/Gmail untuk pautan produk kini commit fail HTML statik terus ke GitHub Pages (bukan sajikan dari Supabase, yang sengaja tak boleh sajikan HTML dengan Content-Type betul) — lihat bahagian "📱 Preview WhatsApp/Gmail untuk Pautan Produk" di bawah (kemaskini besar). Tiada perubahan SQL diperlukan.
> 38. `SQL_TAMBAHAN_35.sql` — Mesej Promosi (Notifikasi Bergerak) di laman utama index.html, ditetapkan pemilik di tab "🎟️ Voucher Diskaun" (pengurusan.html) — lihat bahagian "📢 Notifikasi Promosi Bergerak (Laman Utama)" di bawah.
> 39. Kad baharu **"📣 Hebahan WhatsApp (Marketing)"** di pengurusan.html (Lebih, pemilik sahaja) — lihat bahagian "📣 Hebahan WhatsApp (Marketing)" di bawah. Tiada perubahan SQL/Edge Function diperlukan.
> 40. Unit **"sachet (25g)"** ditambah pada pilihan Unit (Tambah/Edit Produk, tab Stok). Tiada perubahan SQL diperlukan.
> 41. Kad baharu **"👥 Data Pembeli"** di pengurusan.html (Lebih, pemilik sahaja) — senarai pelanggan e-dagang disatukan ikut nombor telefon, untuk susulan & marketing. Tiada perubahan SQL diperlukan.
> 42. `SQL_TAMBAHAN_36.sql` + Edge Function baharu `hantar-emel-susulan` + set secret `RESEND_API_KEY` — susulan emel untuk pesanan belum/gagal bayar, dan butang "🔓 Bebaskan Voucher" untuk guna semula kod voucher yang gagal — lihat bahagian "📧 Susulan Bayaran & Bebas Voucher" di bawah.
> 43. `SQL_TAMBAHAN_37.sql` + Edge Function baharu `susulan-auto-cron` + set secret `CRON_SECRET` + jadual `pg_cron` — susulan emel bayaran AUTOMATIK (1 emel sehari, maksimum 3 kali) & auto-batal pesanan (data pembeli KEKAL direkod) selepas 3 kali tanpa bayaran — lihat bahagian "🔁 Susulan Bayaran Automatik (Harian)" di bawah.
> 44. `SQL_TAMBAHAN_38.sql` — Pembetulan bug padam voucher (FK `baucar_guna` kini `ON DELETE CASCADE`) + lajur `maksima_belanja` pada `baucar` (had maksima belian supaya kod tak disalahguna untuk belian bernilai besar) + butang "✏️ Edit Voucher" — lihat bahagian "🎟️ Voucher Diskaun" di bawah (kemaskini). Tiada bucket Storage baharu diperlukan.
> 45. `SQL_TAMBAHAN_39.sql` — Jadual `wa_hebahan_state` supaya progress kad "📣 Hebahan WhatsApp (Marketing)" disegerak ke cloud (bukan localStorage sahaja) — peranti kedua boleh sambung tugasan hantar mesej dari nombor terakhir — lihat bahagian "📣 Hebahan WhatsApp (Marketing)" di bawah (kemaskini). Tiada bucket Storage baharu diperlukan.
> 46. Shortcut chip di bahagian atas tab Profile (Lebih) — pemilik/pekerja klik satu shortcut terus dibawa scroll ke kad berkaitan (Profil, Voucher, Data Pembeli, dll). Tiada perubahan SQL/Edge Function diperlukan.
> 47. Deploy Edge Function baharu `hantar-emel-pukal` (guna semula secret `RESEND_API_KEY` sedia ada) — butang "📧 Emel Pukal ke Semua Pembeli" di kad "👥 Data Pembeli" untuk hantar SATU emel pemasaran kepada semua pelanggan yang ada rekod emel — lihat bahagian "👥 Data Pembeli" di bawah (kemaskini).
> 48. `SQL_TAMBAHAN_40.sql` — Butang kod voucher di checkout index.html ditukar kepada "🎟️ Guna Kod" (lebih jelas berbanding ✅ sebelum ini), dan pautan "ℹ️ T&C" baharu pada baris "Diskaun Voucher" yang papar modal Terma & Syarat khusus untuk kod yang berjaya digunakan (minima/maksima belanja, tarikh luput, had guna) — `validasi_baucar()` dikemaskini untuk pulangkan medan tambahan ini. Tiada bucket Storage/Edge Function baharu diperlukan.
> 49. Google Analytics 4 (GA4) dipasang pada index.html & pesan.html (tag `gtag.js`), termasuk event `purchase` dihantar setiap kali pesanan berjaya dibuat — untuk aktifkan Key Event "Drive Sales" dalam GA4 Admin → Events. Tiada perubahan SQL/Edge Function diperlukan (cuma tukar Measurement ID di dalam tag jika akaun GA berbeza).
> 50. `SQL_TAMBAHAN_41.sql` — Jadual `kunjungan_web` + kad baharu **"🌐 Trafik Website"** di tab "📈 Analisis" (pengurusan.html, pemilik sahaja) — jejak kunjungan & saluran (Facebook/Instagram/WhatsApp/Google/Direct, dikesan dari UTM param atau referrer) terus dalam apps, tanpa perlu buka Google Analytics — lihat bahagian "🌐 Trafik Website" di bawah.
> 51. `SQL_TAMBAHAN_42.sql` — Jadual `wa_hebahan_batch` + ruangan **"📂 Batch Tersimpan"** & **"💾 Simpan Batch"** di kad "📣 Hebahan WhatsApp" (Lebih, pemilik sahaja) — simpan senarai nombor + mesej sebagai satu batch bernama (cth "Promosi Raya Julai"), pilih semula bila-bila untuk terus buat hebahan tanpa perlu susun semula senarai — lihat bahagian "📣 Hebahan WhatsApp (Marketing)" di bawah (kemaskini).
> 52. `SQL_TAMBAHAN_43.sql` — Tanda kotak **"🚚 Percuma Penghantaran (Free Shipping)"** baharu bila cipta/edit voucher (kad "🎟️ Voucher Diskaun") — bila ditandakan, kos penghantaran diwaive sepenuhnya untuk pesanan yang guna kod tersebut. Dikuatkuasakan di **server** (trigger `validasi_harga_pesanan_edagang` + `validasi_baucar()`), bukan client sahaja — lihat bahagian "🎟️ Voucher Diskaun" di bawah (kemaskini).
> 53. **Pembetulan logik Bonus Kedai Baru** (pengurusan.html) — bonus kini hanya sah selepas kedai buat penghantaran/transaksi PERTAMA (bukan sekadar didaftarkan), dengan kadar berbeza ikut kaedah bayaran transaksi pertama itu: Tunai/Transfer = kadar penuh (default RM10), Consignment/Hutang = kadar rendah (default RM2) + **top-up automatik** (default RM8) bila kedai tu kemudian buat belian tunai/transfer buat kali pertama, supaya jumlah keseluruhan cecah maksimum RM10 (tak lebih). Sebelum ini bonus dibayar serta-merta bila kedai didaftarkan tanpa mengira sama ada kedai itu pernah/akan bertransaksi. Tetapan "Bonus Kedai Baru" dipecahkan kepada 2 medan di Tetapan Kos Operasi. Tiada perubahan SQL diperlukan (logik client-side sahaja) — lihat bahagian "🏪 Bonus Kedai Baru" di bawah (kemaskini besar).
> 54. `SQL_TAMBAHAN_44.sql` + Edge Function baharu `winback-auto-cron` + jadual `pg_cron` mingguan — kad baharu **"🔁 Kempen Win-Back Automatik"** (Lebih → Data Pembeli, pemilik sahaja) hantar emel "kami rindu awak" automatik setiap Isnin kepada pelanggan yang pernah beli tapi sudah lama tak beli lagi, dengan kod voucher pilihan pemilik. **Dimatikan (OFF) secara default** — pemilik perlu aktifkan sendiri di Tetapan. Guna semula secret `RESEND_API_KEY` & `CRON_SECRET` sedia ada — lihat bahagian "🔁 Kempen Win-Back Automatik" di bawah.
> 55. `SQL_TAMBAHAN_45.sql` + Edge Function baharu `rujukan-ganjaran-cron` + jadual `pg_cron` (setiap 15 minit) — **Kod Referral "Bawa Kawan"**: pelanggan kongsi no. telefon sendiri sebagai kod rujukan; kawan yang buat pesanan PERTAMA guna kod tu dapat diskaun (default 10%, disahkan & dikira di server melalui trigger `validasi_harga_pesanan_edagang`), dan bila pesanan kawan itu **disahkan bayar**, perujuk automatik dapat baucar ganjaran (default RM10) via emel. Kad tetapan baharu **"🎁 Kod Referral 'Bawa Kawan'"** (Lebih → dekat Data Pembeli, pemilik sahaja). **Aktif (ON) secara default** (beza dari Win-Back) sebab tiada risiko emel pukal tanpa kelulusan — cuma diskaun/ganjaran ikut tindakan pelanggan sebenar. Guna semula secret `RESEND_API_KEY` & `CRON_SECRET` sedia ada — lihat bahagian "🎁 Kod Referral 'Bawa Kawan'" di bawah.
> 56. `SQL_TAMBAHAN_46.sql` — **Daftar No. Telefon Rujukan Manual** (option tambahan pada Kod Referral) — pemilik boleh daftar terus mana-mana nombor telefon (staf, influencer, rakan niaga) sebagai kod rujukan sah, TANPA perlu nombor itu pernah membeli. Butang "➕ Daftar No. Telefon Rujukan Manual" di kad "🎁 Kod Referral 'Bawa Kawan'". Tiada Edge Function/secret baharu — lihat bahagian "🎁 Kod Referral 'Bawa Kawan'" di bawah (kemaskini).
> 57. **Pembetulan bug Susulan Bayaran Automatik** — ambang "24 jam sejak susulan lepas" yang tepat menyebabkan pesanan kadang-kadang tersekat kekal terlangkau (kelewatan panggilan Resend menyebabkan stem masa tersimpan beberapa saat SELEPAS cron mula, dan potongan masa "24 jam" hari esok pula dikira dari masa mula cron hari itu — sentiasa sedikit lebih awal). Ambang ditukar kepada 20 jam (beri ruang toleransi 4 jam) supaya turun naik kelewatan tak sebabkan susulan terlepas. Edge Function `susulan-auto-cron` dideploy semula. Tiada perubahan SQL diperlukan.
> 58. `SQL_TAMBAHAN_47.sql` — **Maklum & Semak Ganjaran Rujukan** (pembetulan gap komunikasi Kod Referral): (a) banner teaser baharu "🎁 Rujuk kawan & dapat ganjaran!" di laman utama `index.html` (tak bergantung pada mesej promo pemilik) yang buka modal penerangan penuh program rujukan; (b) halaman pengesahan **Billplz** kini turut papar kod rujukan (no. telefon pembeli) selepas bayaran disahkan — sebelum ini terus hilang untuk pembeli Billplz; (c) RPC baharu `semak_ganjaran_rujukan_saya` + ruangan "🔍 Semak Ganjaran Anda" dalam modal rujukan — perujuk boleh semak sendiri kod ganjaran mereka (kod, nilai, status guna, tarikh luput) guna no. telefon, tanpa perlu emel — lihat bahagian "🎁 Kod Referral 'Bawa Kawan'" di bawah (kemaskini).
> 59. `SQL_TAMBAHAN_48.sql` — Kad showcase baharu **"🏆 Produk Paling Laris"** di atas katalog `index.html` — papar sehingga 8 produk paling laku (klik terus bawa & sorot kad penuh dalam katalog di bawah). Sekali jalan, **pembetulan bug** `senarai_produk_awam()`: `jumlah_terjual` sebelum ini hanya kira jualan `transaksi` (consignment/kedai runcit), terus abaikan jualan e-dagang online sebenar — sort "🔥 Paling Laris" & showcase baharu ni kini kira KEDUA-DUA saluran. Tiada Edge Function/secret baharu diperlukan — lihat bahagian "🏆 Produk Paling Laris" di bawah.
> 60. `SQL_TAMBAHAN_106.sql` — RPC `edit_jumlah_transaksi` + butang **"✏️ Edit Jumlah"** (Tab Tempahan > Transaksi, pemilik sahaja, tak termasuk consignment) — betulkan jumlah asal transaksi yang tersilap key-in (cth silap kuantiti/harga) tanpa perlu padam & minta pekerja hantar semula. Jumlah akhir & `kedai.hutang` dikira semula automatik ikut kadar diskaun sedia ada. Rekod audit (`jumlah_diedit_oleh`/`jumlah_diedit_pada`/`jumlah_asal_original`) disimpan.
> 61. `SQL_TAMBAHAN_107.sql` — **Diskaun invois auto dilucuthak bila lewat due**: cron harian `lucuthak-diskaun-harian` (00:30 waktu Malaysia, `pg_cron`) cari invois berdiskaun (`diskaun_peratus > 0`) yang melepasi `tarikh_akhir_bayaran`, naikkan jumlah ke harga penuh & tambah `kedai.hutang` sekali (bukan sekadar amaran paparan). Idempoten (`diskaun_dilucuthak`) — tak caj berganda walau cron jalan berulang. Consignment dikecualikan.
> 62. `SQL_TAMBAHAN_108.sql` + Edge Function baharu `notifikasi-invois-lewat-cron` — emel automatik (guna semula `RESEND_API_KEY`/`CRON_SECRET` sedia ada) kepada **pekerja yang buat penghantaran** DAN **pemilik** untuk semua invois yang melepasi tarikh akhir bayaran — satu emel ringkasan setiap penerima, dihantar **sekali sahaja** per invois (`notifikasi_lewat_dihantar`), bukan diulang setiap hari. Dijadualkan **1 pagi waktu Malaysia** (lepas cron lucuthak diskaun, supaya emel cerminkan jumlah terkini) — sudah dijadualkan & aktif di projek Supabase semasa (jangan jalankan blok `cron.schedule(...)` dalam fail ni lagi, kekal untuk rujukan/pemasangan baharu sahaja — placeholder `<CRON_SECRET>` sengaja tak diisi nilai sebenar dalam fail yg di-commit ke git).
> 63. `SQL_TAMBAHAN_109.sql` — **"Pulang Stok" (pekerja pulangkan stok bawaan dlm keadaan baik) kini wajib pengesahan pemilik dahulu** sebelum kredit balik ke stok gudang boleh jual — sama corak dua-fasa spt "Serah Reject" sedia ada (dulu terus dikredit & auto-disahkan tanpa semakan pemilik). Kad "📦 Serahan Produk" (Tab Stok, pemilik) kini turut senaraikan permohonan pulang stok yang menunggu, bersama reject.
> 64. `SQL_TAMBAHAN_110.sql` + kemaskini Edge Function `notifikasi-invois-lewat-cron` — **Notifikasi Tolak (Web Push)**: jadual `push_subscriptions` (langganan setiap peranti), butang **"🔔 Aktifkan Notifikasi Tolak"** di kad "👤 Profil Saya" (Lebih), dan `sw.js` dikemaskini utk terima & papar notifikasi. Bila invois melepasi tarikh bayaran, pekerja & pemilik kini terima makluman TERUS di telefon (tambahan kepada emel sedia ada, bukan ganti). **Setup wajib** (jika belum, push dilangkau senyap & emel tetap berjalan spt biasa) — lihat bahagian "🔔 Notifikasi Tolak (Web Push)" di bawah.
> 65. Popup automatik **"🔔 Aktifkan Notifikasi Tolak"** kepada pekerja (bukan pemilik) yang belum langgan push — muncul sekali sehari selepas log masuk, berhenti sendiri sebaik diaktifkan. Tiada perubahan SQL diperlukan.
> 66. Edge Function `notifikasi-kelulusan-pemilik` (permohonan padam/cuti/serahan cash/reject perlu kelulusan) turut dikemaskini hantar **Notifikasi Tolak** kepada pemilik SELARI dengan emel sedia ada — guna semula secret `VAPID_PRIVATE_KEY` yang sama, tiada setup tambahan diperlukan jika #64 sudah dibuat.
> 67. `SQL_TAMBAHAN_111.sql` + halaman baharu **`affiliate.html`** — **Sistem Affiliate**: akaun affiliate log masuk sendiri guna Google (bukan sekadar nombor telefon spt Kod Referral sedia ada), permohonan awam → kelulusan pemilik (kad "💰 Sistem Affiliate", Lebih) → kod affiliate diguna pelanggan di checkout `index.html` (diskaun pelanggan + komisen affiliate utk SETIAP pesanan disahkan, bukan sekadar pertama). Komisen matang 14 hari selepas disahkan sebelum boleh dituntut; bayaran transfer bank MANUAL (pemilik sahkan lepas transfer dibuat di luar sistem). Kod affiliate SATU SLOT sahaja di checkout — tak boleh gabung dgn voucher. **Setup wajib** (jika belum, affiliate tak boleh log masuk langsung) — lihat bahagian "🤝 Sistem Affiliate" di bawah.
> 68. `SQL_TAMBAHAN_112.sql` — **Bonus Kedai Terkumpul matang kini tolak cash dipegang pekerja dahulu**: bila pemilik tekan "💰 Bayar Sekarang" (kad "🏪 Bonus Kedai Baru", Lebih), cash tunai yang pekerja masih PEGANG (belum diserah — `kira_cash_dipegang_pekerja()`, port SQL drpd `kiraCashDipegang()` client sedia ada) ditolak DAHULU drpd bonus matang; hanya BAKI dibayar sebagai baucar. Bahagian ditolak direkod sbg `serahan_cash` auto-disahkan (elak dikira 2x). Jika cash dipegang ≥ bonus matang, bonus ditanda dibayar sepenuhnya (nilai sudah offset cash) tanpa baucar RM0 dijana. Tiada setup tambahan diperlukan.
> 69. `SQL_TAMBAHAN_113.sql` — **Terima Bayaran Hutang turut sokong Belian Peribadi** (bukan kedai sahaja): senarai/dropdown "Kedai & Peribadi" (Tab Kedai, kad Terima Bayaran Hutang) kini turut senaraikan pembeli peribadi (`transaksi.kedai_id IS NULL`) yang ada hutang, dikumpul ikut `nama_pembeli`. Sama corak dua-fasa spt kedai (pekerja mohon → pemilik sahkan; pemilik terus rekod). Tiada setup tambahan diperlukan.
> 70. `SQL_TAMBAHAN_114.sql` — **Affiliate boleh tukar kod affiliate sendiri** (butang "✏️ Tukar Kod" di `affiliate.html`, sebelum ini kod hanya ditetapkan sekali oleh pemilik semasa lulus). Turut betulkan bug `affiliate.html` papar kosong selepas log masuk (JS guna `style.display=''` yg tak override CSS `display:none` asas — ditukar `'block'` eksplisit) & tambah meta cache-control elak browser papar salinan lama. Kad "💰 Sistem Affiliate" (pengurusan.html) kini turut papar jumlah komisen diperoleh setiap affiliate. Tiada setup tambahan diperlukan.
> 71. `SQL_TAMBAHAN_115.sql` + `SQL_TAMBAHAN_116.sql` — **Optimumkan prestasi pangkalan data (RLS)**: ikut cadangan rasmi Supabase Performance Advisor — 39 dasar RLS yang panggil `auth.uid()`/`auth.role()`/`is_pemilik()` terus (dinilai semula SETIAP BARIS) kini dibalut `(select ...)` supaya dikira SEKALI setiap query; ~15 jadual yang ada dasar bertindih (cth "pemilik urus semua X" + "pekerja lihat X sendiri" kedua-duanya terpakai serentak) digabung jadi dasar tunggal setiap arahan (SELECT/INSERT/UPDATE/DELETE). Turut tambah 8 indeks pada foreign key bervolum tinggi (`transaksi`, `gps_track`, `kehadiran`, `serahan_produk`, `pesanan_edagang`, `pre_order`, `pelupusan_stok`). **Tiada perubahan kebenaran akses** — semua diuji hidup (simulasi sesi pekerja & pemilik sebenar) sebelum & selepas; Supabase Performance Advisor sahkan kedua-dua amaran (`auth_rls_initplan`, `multiple_permissive_policies`) turun ke 0. Tiada setup tambahan diperlukan.
> 72. `SQL_TAMBAHAN_117.sql` — **Cadangan prestasi tambahan**: 33 indeks baki pada foreign key yang masih tiada liputan (`unindexed_foreign_keys`); cron harian baharu `padam-gps-track-lama-harian` (2 pagi waktu Malaysia) yang pangkas titik GPS sementara (`gps_track`) lebih 90 hari — tak jejas rekod `kehadiran` rasmi, cuma jejak GPS sepanjang syif. Turut selaraskan (`Promise.all`) 7 fungsi render (`renderMenungguBayaranHutang`, `renderStokMobileSemua`, `renderSerahanProdukSemua`, `renderKosStokPergerakan`, `renderSejarahStokGudang`, `renderSenaraiCutiSemua`, `renderLaporanKehadiran`) yang sebelum ni tunggu satu query siap dulu sebelum mula query kedua walaupun tak saling bergantung — kini jalan serentak, kurangkan masa tunggu paparan terutama bila sambungan/latency rangkaian tinggi. Semak juga `select('*')` pada `transaksi`/`gps_track`: `gps_track` sudah pun sentiasa pilih lajur terhad (`lat,lng`) di semua 3 tempat baca; `transaksi` sengaja dikekalkan `select('*')` sebab hampir semua ~30 lajurnya digunakan merata-rata dalam sistem — menyempitkan berisiko pecah ciri secara senyap utk penjimatan yang kecil (195 baris semasa). Tiada setup tambahan diperlukan.
> 73. `SQL_TAMBAHAN_118.sql` — **Push/emel notifikasi bila ada TEMPAHAN E-DAGANG BAHARU masuk** (bukan bug — ciri ni memang belum pernah wujud, disahkan tiada trigger langsung pada `pesanan_edagang` yg sambung ke sistem push). Trigger `trg_notify_pemilik_pesanan_baru` (AFTER INSERT) guna semula Edge Function `notifikasi-kelulusan-pemilik` sedia ada (kini sokong `jenis='Tempahan E-Dagang Baharu'` dgn wording & label "Pelanggan" sesuai jualan, bukan "perlu kelulusan"). Setiap tempahan baharu (index.html/pesan.html, tak kira kaedah bayar) push+emel semua pemilik serta-merta. Diuji hidup — push berjaya sampai (`pushDihantar:2`). Tiada setup tambahan diperlukan (guna semula secret `RESEND_API_KEY`/`VAPID_PRIVATE_KEY` sedia ada); perlu redeploy Edge Function `notifikasi-kelulusan-pemilik`.
> 74. `SQL_TAMBAHAN_119.sql` — **Push/emel notifikasi bila ada TEMPAHAN PRE-ORDER BAHARU masuk** (pesan.html — sambungan #73, pola sama: tiada trigger sedia ada). Trigger `trg_notify_pemilik_preorder_baru` (AFTER INSERT ON `pre_order`) guna semula Edge Function yg sama (kini turut sokong `jenis='Pre-Order Baharu'` dgn label "Kedai"). Diuji hidup — push berjaya sampai (`pushDihantar:2`). Tiada setup tambahan diperlukan; perlu redeploy Edge Function `notifikasi-kelulusan-pemilik` (sekali dgn #73, sama fail).
> 75. Butang **"✏️ Edit Kadar"** pada setiap affiliate aktif (kad "💰 Sistem Affiliate", Lebih, pemilik) — sebelum ni kadar komisen/diskaun cuma boleh ditetapkan SEKALI semasa lulus permohonan, tiada cara ubah selepas aktif. Modal baharu (`modal-edit-kadar-affiliate`) benarkan pemilik tukar kadar bila-bila masa, guna semula RPC `kemaskini_affiliate` sedia ada (backend dah sokong, cuma tak disambung ke UI). Tiada setup SQL/Edge Function tambahan diperlukan.
> 76. `SQL_TAMBAHAN_120.sql` — **Diskaun pelanggan affiliate kini BERSYARAT** (minima belian, default RM500, **editable setiap affiliate** — lajur baharu `minima_belian`). Diskaun cuma terpakai jika subjumlah pesanan >= minima; jika kurang, kod affiliate tetap SAH (checkout tak gagal) tapi diskaun = 0 dgn mesej jelas "Belanja RM_ lagi untuk dapat diskaun". **Komisen affiliate TIDAK terjejas** — affiliate tetap dapat komisen penuh atas SEBARANG pesanan yg guna kod dia, tak kira jumlah (disahkan diuji hidup). Semakan muktamad di SERVER (trigger `validasi_harga_pesanan_edagang`), bukan client sahaja. Medan "Minima Belian (RM)" ditambah pada modal Lulus Permohonan & Edit Kadar (pengurusan.html), dan dipaparkan di affiliate.html (dashboard affiliate sendiri). Tiada setup tambahan diperlukan.
> 77. `SQL_TAMBAHAN_121.sql` — **🚫 GUGURKAN sepenuhnya "Kod Referral 'Bawa Kawan'"** (sistem lama berasaskan no. telefon, changelog #55/#56/#58) — digantikan Sistem Affiliate (#67+) yang lebih sistematik. Dipadam KEKAL: jadual `rujukan_ganjaran` & `rujukan_manual`, lajur `kod_rujukan`/`rujukan_diskaun` (`pesanan_edagang`) & `rujukan_*` (`tetapan`), fungsi `validasi_rujukan`/`semak_ganjaran_rujukan_saya`, cron `rujukan-ganjaran-setiap-15-minit`, Edge Function `rujukan-ganjaran-cron` (fail sumber dibuang dari repo — **fungsi live di dashboard Supabase perlu dipadam manual**, tiada API padam Edge Function). Kad "🎁 Kod Referral" & modal daftar manual dibuang dari pengurusan.html; ruangan kod rujukan, banner teaser & panel "Kongsi & Dapat Ganjaran" dibuang dari index.html. Trigger checkout (`validasi_harga_pesanan_edagang`) kini cuma sokong voucher + affiliate (2 kod, bukan 3). **Data sejarah ganjaran & senarai nombor manual dipadam kekal, tiada cara pulih** — disahkan oleh pemilik sebelum dijalankan. `SETUP_SQL_LENGKAP.sql` turut dikemaskini (fail konsolidasi tak sertakan lagi ciri ni utk pemasangan baharu). Tiada setup tambahan diperlukan.
> 78. `SQL_TAMBAHAN_122.sql` + 2 Edge Function baharu (`ajakan-affiliate-cron`, `notifikasi-komisen-affiliate`) + PWA/push penuh untuk `affiliate.html` — **Kempen Ajakan & Notifikasi Affiliate**:
>     - **Kempen susulan emel automatik**: jadual baharu `ajakan_affiliate` jejak pembeli lama (emel) yang belum jadi affiliate. Cron harian (`ajakan-affiliate-harian`, 3 pagi waktu Malaysia) sync calon baharu drpd `pesanan_edagang` (status disahkan), hantar emel ajakan setiap 3 hari, **maksimum 3 kali**, berhenti automatik bila mereka daftar (padan emel Google mereka) atau cecah had — sama pola dgn `susulan-bayaran-harian` sedia ada.
>     - **`affiliate.html` kini PWA penuh**: manifest baharu (`manifest-affiliate.json`, start_url tersendiri), guna semula `sw.js` sedia ada (dikemaskini — turut cache & fallback offline `affiliate.html` dgn betul, bukan salah papar `pengurusan.html`). Kad baharu "🔔 Notifikasi" dlm dashboard affiliate — butang aktifkan push (guna semula jadual `push_subscriptions` sedia ada, `user_id` automatik ikut `auth.uid()` affiliate sendiri) + butang "📲 Pasang App di Skrin Utama" (`beforeinstallprompt`).
>     - **Popup gesaan berulang**: sekali sehari (localStorage) SEHINGGA affiliate aktifkan push DAN pasang PWA — sama pola dgn gesaan push pekerja sedia ada di `pengurusan.html`.
>     - **Notifikasi komisen langsung ke affiliate**: trigger `cipta_pendapatan_affiliate` dikemaskini — lepas rekod pendapatan berjaya (pemilik sahkan bayaran pesanan yg guna kod mereka), affiliate terus terima push+emel "🎉 Komisen Baharu!" (Edge Function `notifikasi-komisen-affiliate`, sasaran SATU affiliate, bukan semua pemilik). Diuji hidup — emel & trigger payload disahkan betul.
>     - Guna semula secret `RESEND_API_KEY`/`VAPID_PRIVATE_KEY`/`CRON_SECRET` sedia ada — tiada secret baharu diperlukan. Perlu deploy 2 Edge Function baharu di atas.
> 79. `SQL_TAMBAHAN_123.sql` — **Padam kod voucher tertinggal (`RUJUK6SQGRM`, baki drpd sistem rujukan digugurkan) + tambah validasi server pada rekod transaksi kedai**. Ditemui semasa audit diskaun: RPC `submit_penghantaran` (rekod jualan/hantaran oleh pekerja) sebelum ni PERCAYA SEPENUHNYA jumlah/peratus diskaun yang dihantar client — tiada semakan silang dgn harga sebenar di `stok`, beza dgn 2 flow lain (`index.html`/`pesan.html`) yang KEDUA-DUA kira semula subjumlah drpd `harga_jual` sebenar. Kini RPC turut kira semula subjumlah server-side, abaikan jumlah/jumlah_asal/peratus diskaun yang dihantar client (dipaksa guna nilai dikira semula), & paksa diskaun=0 jika bawah minima (dulu bawah minima sebarang peratus lepas tanpa disemak). Diuji hidup — cubaan "tipu" jumlah/peratus berjaya ditangkap & dibetulkan automatik ke nilai sebenar; jualan jujur biasa (bawah minima, hutang) tak terjejas. Tiada setup tambahan diperlukan.
> 80. `SQL_TAMBAHAN_124.sql` — **Baiki `kira_cash_dipegang_pekerja()` — hutang (kedai & peribadi) yang dibayar TUNAI sebelum ni langsung tak dikira sebagai cash dipegang pekerja**. Ditemui semasa siasat kes sebenar (bayaran Pn Liza diterima Nadia): fungsi cuma imbas jadual `transaksi` yang ASALNYA `kaedah_bayaran='tunai'` — bila hutang (asalnya `kaedah_bayaran='hutang'`) dibayar kemudian secara tunai (melalui `permohonan_bayaran_hutang`, disahkan pemilik), lajur asal tak pernah ditukar, jadi cash sebenar yang pekerja kutip "hilang" drpd pengiraan. Turut menjejaskan tolakan cash Bonus Kedai Terkumpul (#68) sebab guna fungsi sama. Kini gabungkan (UNION) cash drpd `transaksi` tunai+selesai DENGAN cash drpd `permohonan_bayaran_hutang` tunai+disahkan, ikut hari kalendar yang sama, sebelum netting harian & tolak serahan cash. Client (`kiraCashDipegang`/`jumlahCashBelumDiselesai`, semua 4 tempat guna) turut dikemaskini sepadan. Diuji hidup dgn data sebenar — nombor cash dipegang pekerja terjejas naik drpd RM58.04 kepada RM123.39 (2 settlement tunai sebelum ni tak dikira). Tiada setup tambahan diperlukan.
> 81. **Baiki baris item resit "double"/bertindih dalam Muat Turun PDF** — dilaporkan pemilik (resit ada nama produk panjang cth "Tamar Cocoa Papan" yang wrap ke 2-3 baris). Punca: baris item guna CSS Grid (`display:grid`) yang `html2canvas` (enjin jana PDF) tak konsisten kira ketinggian baris bila teks wrap berbilang baris — menyebabkan baris item bertindih/nampak berganda dalam PDF walaupun paparan skrin biasa nampak okay. Ditukar kepada jadual HTML sebenar (`<table>`/`<tr>`/`<td>`) yang html2canvas render dgn tepat & konsisten — disahkan via ujian html2canvas langsung (render bersih, tiada tindihan, walaupun nama produk wrap 2 baris). Terpakai pada kedua-dua jenis resit (jualan/invois biasa & resit pelupusan/pertukaran expired). Tiada perubahan pada jumlah/data — cuma pembetulan visual PDF. Tiada setup tambahan diperlukan.
> 82. **Susun semula butang resit + baiki baris ALAMAT/label bertindih (double) yang masih berlaku selepas #81** — pemilik lapor sekali lagi (invois "Pasaraya Sidik Serasi", baris ALAMAT nampak berganda). Ujian html2canvas langsung menunjukkan punca sebenar ialah **pemotongan berbilang muka surat A4** (`jumlahMuka` loop lama), bukan CSS baris — bila tinggi kandungan tak tepat gandaan tinggi muka surat, baki sedikit tercalit/berulang merentasi sempadan. `muatTurunResitPDF()` kini jana **SATU muka surat sahaja, panjang automatik sepadan tepat dgn tinggi kandungan** (jsPDF format tersuai `[210, tinggi]`, bukan A4 tetap dipecah) — hapuskan sepenuhnya risiko pertindihan sempadan muka surat. Turut tukar `.resit-row` (label NO. INVOIS/TARIKH/KEDAI/ALAMAT dll) drpd flexbox kepada jadual (table-cell) — sama sebab spt #81, langkah berjaga-jaga tambahan. **Butang disusun semula**: butang "🖨️ Cetak" (window.print(), memang tak digunakan) **digugurkan sepenuhnya** (fungsi `cetakResit()` dipadam); "📄 Muat Turun PDF" lama dipecah jadi 2 butang — **"📄 PDF"** (gaya asal berbingkai/klasik, class CSS baharu `.resit-box.bingkai` dipasang sementara) dan **"📄 PDF (Cetak)"** (gaya semasa tanpa bingkai, tulisan besar sesuai printer mini — fungsi sama spt sebelum ini). Disahkan via ujian html2canvas langsung — kedua-dua varian render bersih, tiada tindihan, termasuk alamat panjang wrap 3 baris. Tiada setup tambahan diperlukan.
> 83. **Butang "📱 Follow-up" WhatsApp di senarai "📍 Perlu Servis"** (Tab Kedai) — setiap kad kedai lama tak dilawati kini ada butang WhatsApp terus, buka `wa.me` dgn mesej contoh pra-isi (pekerja BOLEH edit sebelum hantar, spt biasa WhatsApp) + pautan `pesan.html?kedai=ID` khusus kedai tu terselit dlm mesej supaya kedai boleh terus repeat order online. Guna semula `formatNoTelefonMY()` sedia ada (normalize 0xx → 60xx). Klik butang tak turut cetuskan klik kad (fokus peta) — `event.stopPropagation()`. Tiada setup tambahan diperlukan.
> 84. `SQL_TAMBAHAN_125.sql` — **Mesej Follow-up WhatsApp (#83) kini ikut nama SEBENAR pekerja yg hantar** (guna lajur `profiles.singkatan` & RPC `kemaskini_profil_sendiri` sedia ada drpd sesi lepas — pekerja tetapkan nama panggilan sendiri di "Profil Saya", cth Aremier=`Aremier`, Nadia=`Amy`) — sebelum ni "📲 Amir: 017-480 9956" dikodkeraskan (hardcode) utk semua pekerja tanpa mengira siapa sebenarnya hantar. Turut tambah kad baharu **"📱 Mesej Follow-up WhatsApp"** (Lebih → Profile, pemilik sahaja) — pemilik boleh ubah **keseluruhan format/teks mesej** guna placeholder `{nama}` (singkatan pekerja semasa), `{telefon}` (no. dia), `{link_pesan}` (pautan pesan.html khusus kedai) — disimpan di `tetapan.mesej_followup_servis`. Shortcut chip baharu "📱 Mesej Follow-up" ditambah di atas Profile. Diuji — placeholder gantian disahkan betul. Tiada setup tambahan diperlukan.
> 85. `SQL_TAMBAHAN_126.sql` — **Senarai Semak Follow-up di "📍 Perlu Servis" (Urus Route)** — tiap kad kedai kini ada dropdown status lepas follow-up WhatsApp: ✅ Masih Ada Produk / 🛒 Nak Tambah Produk / ⏳ Tidak Reply — Follow-up Lagi / ❌ Tidak Berminat (RPC `tanda_followup_servis`, lajur baharu `kedai.followup_status/_pada/_oleh`; RLS `kedai` UPDATE cuma pemilik jadi guna RPC SECURITY DEFINER supaya pekerja pun boleh tandakan). Kedai yang sudah ditandakan automatik "turun ke bawah" senarai (kekal boleh nampak, cuma diberi keutamaan rendah) supaya kedai yang belum diproses kekal di atas. Tanda jadi tidak relevan (dianggap kosong) automatik bila kedai berkenaan betul-betul dilawati semula (last_visit lebih baru drpd tarikh tanda) — elak status lama tersekat walaupun kedai dah repeat order.
> 86. `SQL_TAMBAHAN_127.sql` — **Notifikasi Pemilik utk Permohonan Program Baharu** (borang awam "Jadi Ejen/Affiliate", "Jadi Penghantar", "Jadi Ejen Marketing" — jadual `pemohon_program`) — PUNCA jumpa: jadual ni **tak pernah** ada trigger notifikasi (beza drpd permohonan_cuti/padam/bayaran_hutang/serahan_cash/serahan_produk yg semua dah ada sejak #65/#74/#85/#89) — permohonan baharu senyap masuk DB tanpa emel/push, pemilik cuma perasan bila buka tab "Permohonan Program" secara manual (kes sebenar: satu permohonan affiliate x-masuk notifikasi). Tambah trigger `trg_notify_pemilik_permohonan_program` (AFTER INSERT), guna edge function `notifikasi-kelulusan-pemilik` sedia ada (tiada function/secret baharu). Diuji struktur (insert+rollback sbg anon, tiada ralat).
> 87. **Longgarkan syarat kelayakan Duit Makan (upah harian)** — sebelum ni pekerja perlu (a) ≥5 jam thumb-in→out DAN (b) sekurang-kurangnya 1 jualan berkaedah hutang/transfer/consignment SAHAJA hari sama — jualan tunai tak dikira. Kes sebenar: Nadia 27 Ogos 2026 kerja 11j13m, 6 jualan (semua tunai) → RM10 makan tak dikira walaupun kerja penuh hari terbukti. Kini syarat (b) diringkaskan kepada sekadar **ada ≥1 transaksi jualan hari sama** (apa-apa kaedah bayaran, termasuk tunai) — fungsi `kiraHariLayakMakan()`, `pengurusan.html`. Baucar draf sedia ada yg terjejas (PV-2026-0075, Nadia 27/8) dikemaskini semula (+RM10 makan).
> 88. **Filter Bulanan di Dashboard (Hasil Diterima / Hutang)** — tambah pemilih bulan (`<input type="month">`) + togol "📊 Semua" di atas stat-grid dashboard, default ikut **bulan terkini**. "Hasil Diterima" & "Hutang" kini dikira ikut skop terpilih (label stat turut papar nama bulan, cth "Hasil Diterima (Ogos 2026)"); bila "Semua" ditogol, kekal 100% sama macam sebelum ini (Hutang pemilik guna `kedai.hutang` — baki tertunggak semasa sebenar). "Kedai Aktif"/"Produk"/"Cash Dipegang" kekal snapshot semasa (bukan jumlah tempoh) — tidak terjejas filter ini sebab ia bukan jumlah transaksi bertempoh.
> 89. **Pecahan Hutang vs Consignment** (Analisis pemilik + Dashboard pekerja) — sebelum ni "Hutang Semasa" (Analisis) & "Hutang" (Dashboard, termasuk legacy "Semua" #88) mencampurkan DUA kaedah bayaran berlainan (`hutang` + `consignment`) jadi satu nombor, guna medan agregat `kedai.hutang`. Kini dipecah kepada 2 stat berasingan di kedua-dua tempat — **Hutang Semasa (Tulen)** & **Consignment Semasa** (Analisis); **Hutang** & **Consignment** (Dashboard, ikut skop filter bulanan #88 & skop pekerja/pemilik sedia ada — termasuk mod "Semua", tiada lagi laluan legacy `kedai.hutang`). Dikira terus drpd `transaksi` ikut `kaedah_bayaran`, bukan lagi drpd `kedai.hutang` yg tak boleh dipisah. Kad "Kedai Hutang Tertinggi"/"Kedai Consignment Tertinggi" (Analisis) dikekalkan, kini kongsi pengiraan yg sama dgn stat di atas (elak duplikasi kod).
> 90. `SQL_TAMBAHAN_128.sql` — **Baiki `sahkan_jualan_konsainan()` — kreditkan balik `stok_pekerja` bila barang consignment dipulangkan** (siasatan aduan Nadia "stok tak tally", cth Tamar Cocoa Papan). Punca: `submit_penghantaran()` tolak `stok_pekerja` SEPENUHNYA (ikut kuantiti dihantar) semasa transaksi consignment dicipta, termasuk barang yang akhirnya tak laku — bila barang tu disahkan "pulang" (qtyPulang) via `sahkan_jualan_konsainan()`, fungsi asal cuma kemaskini rekod transaksi, **tak pernah** kreditkan balik kuantiti ke `stok_pekerja`, jadi barang "hilang" kekal drpd sistem walaupun secara fizikal kembali ke beg pekerja. Nasib baik ciri "pulang consignment" belum pernah digunakan sebenar (0 rekod `items_pulang` wujud) — bukan punca percanggahan sedia ada, tapi pasti akan berulang bila ciri ni mula digunakan. Diuji live (insert+rollback) — baki `stok_pekerja` naik betul ikut qtyPulang. Turut betulkan `stok_pekerja` Nadia (S003 Tamar Cocoa Papan) kepada 0 ikut kiraan fizikal sebenar (jurang sejarah ~28 unit sebelum tempoh boleh disahkan, tiada rekod menerangkannya — kemungkinan pertukaran/berian stok terus antara pekerja tanpa guna butang "Pindah ke Pekerja", atau pembetulan manual lampau).
> 91. **3 ciri pemantauan keluar-masuk stok** (susulan siasatan #90) — (a) **📜 Sejarah Pergerakan per-produk** (pekerja) — tap mana-mana produk di "🎒 Stok Bawaan Saya" untuk lihat kronologi ambil/pulang/pindah/jualan/pulang-consignment/lupus 90 hari terkini, baki dikira ANCHOR pada baki sistem SEBENAR semasa (bukan andaian mula drpd 0) supaya sentiasa padan realiti walaupun ada jurang sejarah lampau; (b) **🔍 Semak Percanggahan Stok Pekerja** (Analisis, pemilik) — jalankan semakan sekali klik merentasi SEMUA pekerja × produk, bandingkan baki sistem vs jangkaan drpd sejarah penuh, senaraikan mengikut saiz beza terbesar — senarai keutamaan utk kiraan fizikal, bukan tuduhan ralat automatik; (c) **Peringatan kiraan fizikal selepas Thumb In** — toast kecil lembut muncul ~4 saat selepas Thumb In berjaya, ajak pekerja sempatkan semak stok bawaan sepadan dgn sistem sebelum mula bergerak — tangkap percanggahan awal sebelum bertimbun jadi aduan besar.
> 92. `SQL_TAMBAHAN_129.sql` — **Mod Paparan Route: 🌐 Semua Kedai vs 👤 Ikut Pendaftar** (Urus Route, "📍 Perlu Servis") — pemilik kini PILIH secara eksplisit (2 butang, sebelum tekan "+ Cipta", atau tukar lagi selepas cipta di senarai route) sama ada kedai dlm route tu kelihatan di "Perlu Servis" SEMUA pekerja, atau HANYA pekerja yg mendaftarkan kedai berkenaan (`kedai.didaftarkan_oleh`). Sebelum ni "Perlu Servis" pekerja ditapis ikut SEJARAH TRANSAKSI (pernah jual di situ) — tiada kaitan langsung dgn route/pendaftar, pemilik tiada cara kawal terus. Kini `renderServisKedai()` skop kedai ikut mod route (default `pendaftar`, kedai tanpa route pun jatuh balik ke mod ni). Lajur baharu `route_kedai.mod_paparan`, RPC `tukar_mod_paparan_route` (pemilik sahaja). Diuji live (rollback) — RPC tukar mod berjaya.
> 93. **Susunan keutamaan, tamat tempoh automatik & filter status di "📍 Perlu Servis"** — (a) Senarai kini disusun: kedai BELUM ditanda (tempoh paling lama sejak penghantaran TERAKHIR di atas sekali) → kedai SUDAH ditanda (ikut keutamaan status ⏳ Tidak Reply > ✅ Masih Ada Produk > 🛒 Nak Tambah > ❌ Tidak Berminat) → kedai yang LANGSUNG TAK PERNAH ada penghantaran diletak DI BAWAH SEKALI (fungsi `susunPerluServisIkutKeutamaan()`, gantikan susunan jarak GPS dalam route yg sebelum ni tak selaras dgn tujuan senarai — keutamaan tindakan, bukan laluan memandu). (b) Tanda status kini **tamat tempoh automatik**, kembali ke "Tandakan status follow-up…" lepas: ⏳ Tidak Reply 2 hari, ✅ Masih Ada Produk 14 hari, 🛒 Nak Tambah 30 hari (❌ Tidak Berminat kekal sehingga diubah manual). (c) Dropdown filter baharu di bawah peta — tapis senarai ikut status (Semua / Belum Ditandakan / salah satu 4 status).
> 94. `SQL_TAMBAHAN_130.sql` — **Seragamkan nama kedai (Huruf Besar Awal Setiap Perkataan)** — cth `"AA YON ENTERPRISE"` → `"Aa Yon Enterprise"`, `"nabila goreng pisang sungai petani"` → `"Nabila Goreng Pisang Sungai Petani"`. Guna `INITCAP()` Postgres: (a) kemaskini SEMUA 202 rekod kedai sedia ada sekali sahaja; (b) trigger `trg_seragam_nama_kedai` (BEFORE INSERT/UPDATE OF nama) — kedai BAHARU atau nama yg diubah PADA MASA DEPAN (dari mana-mana laluan — daftar kedai baharu di apps, kemaskini profil kedai, dll) automatik diseragamkan sama, tiada perlu ubah kod client. Nota: `INITCAP` tak kekalkan singkatan huruf besar penuh (cth "MSA"→"Msa", "KTM"→"Ktm") — had biasa title-case automatik; boleh dibetulkan manual utk nama tertentu jika perlu. Diuji live — bulk update disahkan + insert ujian (rollback) sahkan trigger berfungsi.
> 95. `SQL_TAMBAHAN_131.sql` — **Kekalkan singkatan huruf besar penuh dalam nama kedai** (susulan #94/nota di atas) — fungsi baharu `smart_titlecase()` gantikan `INITCAP()` polos: token pendek (2-4 huruf) yang ASALNYA huruf besar sepenuhnya (cth MSA, KTM, JMJ, BPJ, RNF, ABC, PPK) kini DIKEKALKAN, bukan ditukar jadi "Msa"/"Ktm". Trigger `seragam_nama_kedai()` dikemaskini guna fungsi baharu ni — kesan pada kedai BAHARU/nama diubah pada masa depan juga. Betulkan 31 rekod sedia ada yang #94 tersalah tukar singkatan. Diuji live (rollback) — insert "ABC mart NEW testing SDN BHD" betul jadi "ABC Mart NEW Testing SDN BHD" (ABC/NEW/SDN/BHD kekal, mart/testing jadi Title Case).
> 96. **Pemaklumam Untung/Rugi Harian sebelum Thumb Out** — sebelum rekod Thumb Out benar-benar diproses, pekerja kini dipaparkan modal "📊 Ringkasan Hari Ini" — kiraan Untung Bersih SYARIKAT khusus utk pekerja+hari itu sahaja (Untung Kasar jualan hari tu tolak kos upah/minyak/makan/bonus kedai baru/upah e-dagang hari tu — formula SAMA spt "Laporan Harian" pemilik, mod tapis 1 pekerja, diekstrak ke fungsi baharu `kiraUntungBersihHarianPekerja()` supaya pekerja sendiri boleh panggil). Negatif → "😔 Maaf, Syarikat Rugi Hari Ini" (merah); positif/sifar → "🙏 Terima Kasih, Syarikat Untung Hari Ini!" (hijau) — mesej ringkas sahaja, **tiada jumlah RM/pecahan kos dipaparkan kpd pekerja** (nombor sensitif kekal kpd pemilik di Laporan Harian). Pekerja WAJIB tekan "✅ Faham, Teruskan Thumb Out" (atau "↩️ Batal, Kembali Bekerja") sebelum rekod Thumb Out sebenar disimpan — batal = sesi kekal aktif, boleh cuba semula bila-bila. Gagal senyap (terus proses Thumb Out spt biasa) jika pengiraan gagal — bukan sekatan kritikal.
> 97. **Baiki "🧾 Jana Baucar Bulan Ini" — pesanan e-dagang tersalah bulan** — punca "macam ada masalah": `renderLaporan()`/`renderUpahSaya()` kira kelayakan upah e-dagang ikut `created_at` (tarikh order di-key-in) SAHAJA, sedangkan 3 fungsi lain (`renderLaporanHarian()`, `kiraUpahPenuhHari()`, `kiraUntungBersihHarianPekerja()`) semua guna `updated_at||created_at` (tarikh SEBENAR dihantar/selesai). Kesan sebenar disahkan (8 pesanan sebenar): order di-key-in Julai tapi baru dihantar/selesai Ogos — Laporan Bulanan/baucar Julai KIRA upah tu (patut masuk Ogos), Ogos pula TERCICIR. Dibetulkan konsisten guna `updated_at||created_at` di kedua-dua fungsi. Turut baiki `janaBaucarBulanIni()` — ralat RPC dulu terus dibuang senyap (`ralat++` sahaja, sebab kegagalan tak pernah dipaparkan); kini sebab sebenar dipaparkan dalam toast + senarai penuh di console. **Baucar draf sedia ada (belum diluluskan) utk Julai/Ogos pekerja terjejas perlu dijana semula (tekan "Jana Baucar Bulan Ini" sekali lagi) supaya guna kiraan yang dah dibetulkan.**
> 98. **Susun Baucar Harian ikut tarikh terkini di atas** — `renderBaucarSaya()`/`renderBaucarList()` sebelum ni susun ikut `no_siri` (nombor siri cipta, tak semestinya sepadan urutan tarikh — terutama bila baucar dijana semula/dikemaskini). Kini disusun ikut `tarikh` (baucar harian) atau awal `bulan` (baucar bulanan tiada `tarikh`) TERKINI di atas sekali, `no_siri` sekadar pemisah seri (tie-break) bila tarikh sama.
> 99. **Baiki "🧾 Jana Baucar Bulan Ini" — "tekan tapi tiada apa keluar"** — disahkan drpd DB, RPC memang berjaya cipta baucar (bukan ralat #97), tapi PENGALAMAN pemilik nampak macam gagal disebabkan 2 isu: (a) kad "🧾 Baucar Bayaran" (tempat baucar baharu dipaparkan) terletak JAUH di bawah kad "📊 Laporan Bulanan" (tempat butang ditekan) — kini `janaBaucarBulanIni()` auto-scroll ke kad tu lepas siap; (b) baucar BULANAN (petrol/upah/makan) tiada lajur `tarikh` (cuma `bulan`) — jika "Tapis Tarikh" masih aktif drpd tapisan sebelum ni (cth semak baucar harian hari tertentu), SEMUA baucar bulanan baharu tersembunyi (v.tarikh=null tak sepadan tapisan) — kini tapisan tarikh dikosongkan automatik lepas jana baucar bulanan.
> 100. **📄 Muat Turun PDF Laporan & Baucar Bulanan** — butang baharu di kad "📊 Laporan Bulanan" (pemilik) hasilkan SATU dokumen PDF utk direkod/fail — gabung ringkasan kewangan (Hasil, Hutang, Untung Kasar, Kos Operasi penuh, dan **UNTUNG BERSIH** diserlahkan), Pecahan Upah Ikut Pekerja, dan Senarai penuh Baucar Bayaran bulan tu (no. siri/pekerja/kategori/jumlah/status) — dalam SATU fail, bukan perlu muat turun satu-satu baucar berasingan. Guna angka SAMA yg pemilik dah nampak di skrin (`LAPORAN_RINGKASAN_TERKINI`, disimpan sekali oleh `renderLaporan()` — tiada pengiraan baharu, elak PDF beza drpd Laporan di skrin). Muka surat TUNGGAL disesuaikan tinggi kandungan sebenar (sama pendekatan yg dibetulkan utk PDF resit — elak isu pertindihan sempadan muka surat A4 berbilang).
> 101. **📅 Tarikh Luput per-item (Optional) di Tab Hantar** — bila rekod jualan/penghantaran, setiap item kini ada medan "Tarikh Luput" pilihan (bukan wajib) — auto-isi lalai drpd tarikh luput produk (Stok, jika pemilik dah tetapkan) tapi kekal **boleh diedit/dikosongkan** ikut batch sebenar dihantar (batch berlainan boleh ada tarikh luput berbeza drpd rekod produk). Dipapar di SEMUA resit & invois (fungsi `renderResit()` dikongsi merentasi paparan skrin, PDF bingkai/borderless, dan hantar WhatsApp) — baris kecil "⏳ Luput: [tarikh]" di bawah nama produk, cuma muncul kalau diisi. Disimpan terus dlm `transaksi.items[].tarikhLuput` (JSONB, tiada migration SQL diperlukan).
> 102. **Baiki "Bayar Sekarang" (Bonus Kedai Baru Terkumpul) — jumlah tak kelihatan semasa sahkan** — butang sedia ada dah papar jumlah (cth "💰 Bayar Sekarang (RM616.63)"), tapi dialog konfirmasi selepas tekan cuma tanya "Sahkan bayar SEMUA bonus..." TANPA nyatakan semula angka — pemilik terpaksa ingat/anggar semasa keputusan akhir. Kini dialog konfirmasi papar jumlah eksplisit + amaran baki sebenar mungkin lebih rendah (cash dipegang pekerja ditolak dahulu). Lepas bayar berjaya, sistem auto-tapis "🧾 Baucar Bayaran" ke bulan+pekerja berkenaan & scroll terus ke situ — baucar (kategori Bonus Kedai Baru, atau digabung Upah Harian jika ditick) terus kelihatan dgn butang 📄 PDF/📱 WhatsApp Pekerja sedia ada utk terus kongsi kepada pekerja (sama isu "tekan tapi tiada apa keluar" yg dibaiki utk Jana Baucar Bulan Ini #99).
> 103. **`ads.txt` + Google AdSense Auto Ads** (`index.html`, laman awam) — punca AdSense "tidak aktif": (a) tiada fail `ads.txt` di root domain (404 di laman langsung) — Google WAJIBKAN ini utk sahkan akaun AdSense sbg penjual sah, tanpanya paparan iklan disekat/dihadkan; (b) pustaka `adsbygoogle.js` dimuatkan tapi TIADA unit iklan/Auto Ads diaktifkan langsung — tiada iklan pernah diminta. Tambah `ads.txt` (`google.com, pub-7108647195034391, DIRECT, f08c47fec0942fa0`) + aktifkan Auto Ads (`enable_page_level_ads: true`) di `index.html`. Disahkan berkesan — dashboard AdSense terus papar "Verify site ownership" ✅ & "Review requested" ✅ (peringkat semakan Google, bukan lagi tersekat kod).
> 104. `SQL_TAMBAHAN_132.sql` — **Deskripsi Produk (SEO)** — jadual `stok` sebelum ni HANYA ada nama/kategori/harga/unit, tiada medan penerangan. Kesan SEO sebenar: `kemaskiniSEOProduk()` (index.html) & edge function `produk-preview-gen` kedua-dua jana "description" Product schema drpd TEMPLAT generik SAMA (nama+kategori+harga sahaja) utk SETIAP produk — kandungan hampir serupa merentasi semua halaman produk ("thin/duplicate content", menyukarkan Google beza & ranking-kan produk secara individu). Tambah: (a) lajur `stok.deskripsi` (pilihan) + medan borang "Deskripsi Produk" baharu di Tambah/Edit Produk (pengurusan.html); (b) RPC `senarai_produk_awam()` dikemaskini sertakan lajur ni (senarai lajur pulangan eksplisit, tak automatik terikut ALTER TABLE); (c) `index.html` papar deskripsi (dipangkas 2 baris) di kad produk kedai online, guna deskripsi sebenar dlm Product schema + meta description (fallback templat lama jika kosong); (d) edge function `produk-preview-gen` turut guna deskripsi sebenar utk pratonton kongsi pautan (WhatsApp/Facebook). **Perlu tindakan pemilik**: isi deskripsi utk setiap produk (Stok > Edit) supaya manfaat SEO sebenar — lajur kosong (`null`) buat masa ini utk semua produk sedia ada, jatuh balik ke templat lama automatik sehingga diisi.
> 105. `SQL_TAMBAHAN_133.sql` — **🚨 Baiki "Gagal muat senarai produk" di laman kedai online** (regresi susulan #104) — bila RPC `senarai_produk_awam()` di-`DROP FUNCTION` + `CREATE` semula (wajib sebab senarai lajur pulangan berubah, `CREATE OR REPLACE` polos gagal), SEMUA kebenaran `GRANT EXECUTE` sedia ada turut hilang bersama objek lama (objek baharu mula dgn grant kosong). RPC ni dipanggil setiap pelawat AWAM (belum log masuk, role `anon`) utk papar katalog produk — bila `anon` hilang kebenaran, panggilan gagal → mesej merah "Gagal muat senarai produk — sila cuba lagi kemudian" terpapar kpd SEMUA pelanggan (kedai online nampak kosong). Baiki: `GRANT EXECUTE` semula kpd `anon` & `authenticated`. Disahkan live — `has_function_privilege()` kembali `true` utk kedua-dua role. **Nota masa depan**: setiap kali RPC awam kena DROP+CREATE (bukan CREATE OR REPLACE), WAJIB GRANT EXECUTE semula serta-merta selepas tu.
> 106. `SQL_TAMBAHAN_134.sql` — **Pelarasan Kos Pekerja** — padam transaksi (cth kedai pulangkan/batal pesanan) SELEPAS baucar harian pekerja hari tu dah **diluluskan/dibayar** dulunya terus `SET status='dibatalkan'` pada baucar tsb — tapi duit SEBENAR dah/hampir dipindah kpd pekerja, jadi "membatalkan" rekod cuma buat ia tak konsisten dgn realiti (nampak macam tak pernah dibayar walhal dah). Kini: (a) baucar lama DIKEKALKAN status asal (audit trail utuh); (b) jadual baharu `pelarasan_kos_pekerja` rekod kos upah (dikira server-side drpd `stok.upah_pekerja`) + kos minyak (anggaran client-side — beza jarak sesi kehadiran DENGAN vs TANPA transaksi tu dlm laluan, `kiraMinyakPulihTransaksi()`) transaksi yg dipadam; (c) `cipta_baucar_harian()` automatik TOLAK jumlah pelarasan tertunggak pekerja tu drpd baucar HARIAN SETERUSNYA yg dijana (bukan yg lama, dah dikunci) & tanda "sudah_diselaraskan" — "kos hari ni dipulihkan drpd baucar akan datang". Baucar & resit papar baris "🔻 Pelarasan Kos Dipulangkan" bila berkenaan; kad baharu "Pelarasan Kos Tertunggak" (pemilik, atas senarai Baucar Bayaran) papar telus apa yg belum diselaraskan ikut pekerja. `padam_transaksi_kedai()` kini pulangkan `jsonb` (dulu `void`) supaya UI terus maklum jumlah pelarasan yg dicipta.
> 107. `SQL_TAMBAHAN_135.sql` — **🚨 Baiki "column reference item is ambiguous" bila padam transaksi kedai** (regresi susulan #106, ditemui serta-merta oleh pemilik cuba padam) — query baharu (kira kos upah transaksi) di #106 guna alias `item` utk `jsonb_array_elements(...)`, tapi `item` JUGA nama pembolehubah plpgsql sedia ada (loop var stok/serahan_produk dlm fungsi sama) — Postgres tak dapat selesaikan `item->>'qty'` (pembolehubah vs alias jadual), lalu SETIAP cubaan padam transaksi (apa-apa transaksi) gagal. Baiki: tukar alias kepada `itm` (tak berlanggar). Diuji live (BEGIN/ROLLBACK) sebelum disahkan kpd pemilik — pulangkan jumlah upah/minyak/pelarasan betul tanpa ralat.
> 108. **Baiki tab "📍 Kehadiran & Jarak Pekerja" tercicir sesi lepas tengah malam UTC** — `renderLaporanKehadiran()` tapis `kehadiran.thumb_in_masa` (disimpan UTC) terus guna tarikh mentah (`tarikh+'T00:00:00'`/`'T23:59:59'`) TANPA tolak offset +08:00 Malaysia — sesi yg bermula sblm 8 pagi waktu Malaysia (cth 7:52 pagi MYT = 23:52 UTC **hari sebelumnya**) tercicir drpd carian "hari ini" (pemilik pilih tarikh hari ini, tapi sesi pekerja "tersembunyi" sbb rekodnya berlabel tarikh UTC semalam). Isu SAMA yg dah dibaiki di `kiraJarakKehadiranJulat()` sblm ni (lihat nota kod di situ) — tertinggal cuma di fungsi laporan Kehadiran ni. Baiki: guna helper `keUTC()` yg sama (tandakan +08:00 sblm hantar ke Supabase). Ditemui bila pemilik laporkan pekerja "hadir tapi tak papar" pd tab Kehadiran walhal thumb-in sah direkod.
> 109. `SQL_TAMBAHAN_136.sql` — **🔴🟡🟢 Indikator Sah Lokasi Kedai** — pin lokasi kedai diletak MANUAL (seret/klik peta/cari alamat) semasa daftar/edit, TIADA semakan langsung sebelum ni — pin tersasar terus jejaskan kiraan km/minyak dlm Laporan & Baucar Harian (lihat siasatan sebenar Agrobazaar Seri Indah Bakery, Sep 2026, ~22km terasing). Tambah: (a) lajur `kedai.jarak_pin_gps_km` — jarak pin↔GPS semasa PEKERJA masa daftar/edit (null = tak dpt disahkan, cth pemilik daftar drpd pejabat); (b) badge LIVE 🟢≤2km/🟡2-5km/🔴>5km bawah peta borang Daftar/Edit Kedai, kemaskini automatik setiap kali pin bergerak (drag/klik/cari/GPS-button); (c) amaran `confirm()` sblm simpan jika pekerja & jarak >5km (boleh teruskan lepas sah sedar, tak block terus); (d) **kad amaran BAHARU dlm senarai Baucar Bayaran** (pemilik) SEBELUM luluskan baucar harian — gabung 2 isyarat: pin jauh drpd GPS (data baharu) DAN/ATAU kedai terasing >15km drpd kedai lain yg dilawati hari sama (isyarat sejagat, berfungsi utk kedai LAMA jugak tanpa perlu data GPS baharu).
>
> Tak perlu jalankan `SETUP_SQL_LENGKAP.sql` semula jika projek Supabase anda dah aktif (fail itu sudah dikemas kini dengan pembetulan yang sama untuk pemasangan BAHARU).

### 🚨 Keselamatan — jalankan SQL_TAMBAHAN_17.sql SEGERA
Semasa semakan sistem, ditemui celah pada laman e-dagang (`index.html`): dasar RLS untuk `pesanan_edagang` sengaja dibuka (`WITH CHECK (true)`) supaya *guest checkout* boleh insert pesanan tanpa akaun — tapi ini bermakna sesiapa yang tahu `anon key` (kunci awam, memang terdedah dalam kod laman — bukan rahsia) boleh hantar permintaan terus ke Supabase (tanpa perlu guna borang checkout langsung) dengan:
- **Harga produk apa sahaja** (cth: RM1000 barang ditetapkan sebagai RM0.01)
- **`status_bayaran` terus kepada `'disahkan'`** — pesanan nampak "sudah bayar" tanpa bayar langsung

`SQL_TAMBAHAN_17.sql` tambah *trigger* yang kira semula harga setiap item daripada jadual `stok` sebenar (abaikan apa sahaja client hantar) dan paksa `status_bayaran` sentiasa `'menunggu'` bila pesanan dicipta — pengesahan sebenar hanya boleh berlaku melalui staff log masuk atau webhook Billplz yang disahkan. Checkout normal (borang di laman) **tidak terjejas langsung** — trigger ini hanya mengira semula nilai yang sepatutnya sama dengan apa borang dah hantar.

Celah yang sama wujud pada borang repeat-order kedai (`pesan.html`) — jadual `pre_order` — dibaiki oleh `SQL_TAMBAHAN_18.sql`, yang kira semula `jumlah_asal`/`diskaun_peratus`/`jumlah_selepas_diskaun` daripada harga stok & tetapan diskaun sebenar, dan turunkan automatik `bayar_metod` daripada `consignment` ke `cod` jika jumlah melebihi had consignment yang ditetapkan pemilik.

### 🗺️ Google Maps (menggantikan OpenStreetMap)

Sistem kini guna **Google Maps** untuk peta pilih lokasi kedai, peta servis, dan lokasi live pekerja. Anda perlu API key sendiri:

1. Pergi **console.cloud.google.com** → cipta project baharu (atau guna sedia ada)
2. Aktifkan **Billing** (perlu kad kredit — Google beri free tier ~$200/bulan percuma, cukup untuk perniagaan kecil)
3. Pergi **APIs & Services → Library** → aktifkan **"Maps JavaScript API"** dan **"Geocoding API"**
4. Pergi **APIs & Services → Credentials** → **Create Credentials → API Key**
5. (Disyorkan) Sekat key tersebut kepada domain `www.wafitijarahtrading.com/*` sahaja (API Key → Application restrictions → HTTP referrers) — tambah `biz-free.github.io/*` sekali sepanjang tempoh peralihan domain
6. Buka fail `pengurusan.html`, cari `const GOOGLE_MAPS_API_KEY = 'YOUR_GOOGLE_MAPS_API_KEY';`, ganti dengan key sebenar anda
7. Upload semula ke GitHub

> 💡 Pautan "Lihat di Google Maps" pada kad kedai **tidak perlukan API key** — ia buka terus aplikasi/laman Google Maps di peranti pekerja sendiri. Hanya peta INTERAKTIF (pilih lokasi, peta servis, lokasi live) yang perlukan API key.

## 📱 Cara Install Apps ke Phone (APK / PWA)

### Langkah 1 — Host apps (percuma)

**Pilihan A: GitHub Pages (Disyorkan, 100% Percuma)**
1. Daftar akaun di github.com
2. Klik "New Repository" → nama: `wafi-app`
3. Upload semua fail (index.html, pengurusan.html, pesan.html, manifest.json, sw.js, icon-192.png, icon-512.png)
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

### 🔑 Reset Kata Laluan Pekerja ke "abc123" (Pemilik sahaja)
Di **Lagi → Urus Pekerja**, pemilik boleh tekan **"🔑 Reset abc123"** pada mana-mana pekerja yang lupa kata laluan. Pekerja tersebut akan diminta **tetapkan kata laluan baharu** (tak boleh abc123 semula) sebelum boleh masuk ke ruang utama pada log masuk seterusnya.

> ⚠️ **Kenapa hanya pemilik boleh buat ini (bukan sesiapa dari skrin log masuk)?** Jika sesiapa boleh reset password akaun lain ke nilai tetap (abc123) hanya dengan tahu e-mel — itu jadi lubang keselamatan (curi akaun). Sebab itu tindakan ini perlu pengesahan pemilik yang sudah log masuk, dan dijalankan melalui **Edge Function** (kod pelayan berasingan yang pegang kunci admin Supabase secara selamat — kunci ini TIDAK PERNAH masuk ke dalam kod `pengurusan.html` yang orang ramai boleh lihat).

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
6. Selesai — butang "Reset abc123" dalam apps akan berfungsi selepas ini.

### 👍👎 Thumb In / Thumb Out (Kehadiran Pekerja)
Di Dashboard, pekerja tekan **"👍 Thumb In"** untuk mula kerja dan **"👎 Thumb Out"** untuk tamat kerja. Setiap kali, telefon akan minta pengesahan **fingerprint/Face ID sedia ada di telefon tersebut** (WebAuthn) — kali pertama guna, pekerja akan diminta daftar fingerprint/Face ID dahulu (sekali sahaja per peranti).

> ⚠️ **Had sebenar**: Website **tidak boleh** mengimbas cap ibu jari terus seperti mesin kehadiran pejabat — ia guna ciri fingerprint/Face ID yang SEDIA ADA pada telefon pekerja untuk sahkan identiti (standard moden, selamat). Pengesahan ini disahkan di peringkat **peranti/pelayar** sahaja dalam versi ini (bukan disahkan semula secara kriptografi di server) — memadai untuk rekod kehadiran dalaman, tapi jika perlukan tahap lebih tegas (contoh untuk tujuan audit rasmi), boleh ditambah baik lagi dengan Edge Function tambahan pada masa depan.

### 📍 Jejak GPS & Anggaran Jarak (Claim Minyak)
Bermula dari Thumb In sehingga Thumb Out, GPS peranti pekerja **aktif berterusan** (`watchPosition`) — setiap kali peranti kesan pergerakan lokasi, titik baru direkod (ditapis maksimum sekali seminit supaya jadual data tak terlalu besar), ditambah titik lokasi semasa Thumb In & Thumb Out sendiri. Pemilik boleh lihat anggaran jarak (km) dan kos minyak setiap sesi kerja di **Lagi → Kehadiran & Jarak Pekerja** (pilih tarikh).

> ⚠️ **Had sebenar GPS web app**: Penjejakan ini **hanya berfungsi selagi apps dibuka** (tab/PWA di latar depan). Ia BUKAN apps GPS khusus seperti Grab Driver — bila skrin telefon dikunci lama atau apps ditutup, penjejakan terhenti sehingga apps dibuka semula. Ini adalah had platform web (bukan boleh diperbaiki tanpa jadi apps mudah alih asli/native). Anggaran jarak dikira dari titik-ke-titik (garis lurus), bukan jarak jalan sebenar — sesuai sebagai rujukan kasar untuk claim, bukan ukuran GPS profesional.

### 👥 Urus Pekerja (Daftar Terus Dalam Apps)
Pemilik boleh daftar akaun pekerja baru terus dari **Lagi → Urus Pekerja** (nama, e-mel, no. telefon, kata laluan sementara) tanpa perlu masuk dashboard Supabase setiap kali. Sistem guna sambungan sementara (session berasingan) supaya sesi log masuk pemilik sendiri tidak terjejas semasa proses ini.

> ⚠️ Jika akaun pekerja baru tak boleh log masuk serta-merta ("Email not confirmed"), pergi ke Supabase → **Authentication → Providers → Email** dan matikan "Confirm email" — supaya akaun terus aktif sebaik didaftarkan tanpa perlu sahkan e-mel.

### 🔗 Link & QR Pre-Order untuk Kedai (Repeat Order)
Satu link awam **`pesan.html`** (cth: `https://www.wafitijarahtrading.com/pesan.html`) boleh dikongsi terus dengan mana-mana kedai — borang ini kini **interaktif & bergambar**: kedai layari katalog produk (gambar, harga, unit) dan guna butang +/− untuk tambah ke troli, TANPA perlu log masuk. Pesanan masuk terus ke tab **Hantar → Pre-Order** dalam apps (nampak oleh pemilik & pekerja) untuk diproses jadi penghantaran sebenar.

Setiap resit turut jana **kod QR unik** yang terus bawa kedai tersebut ke `pesan.html?kedai=<id kedai>` — bila diimbas, nama & no. telefon kedai automatik terisi (kedai tak perlu taip semula), memudahkan repeat order terus dari resit lama.

### 🛒 Laman E-Dagang B2C (`index.html`) — Fasa 1
Laman utama terbuka untuk pelanggan awam (bukan kedai runcit) beli terus secara runcit: `https://www.wafitijarahtrading.com/`. Guna semula katalog produk yang sama (Stok), tetapi checkout berasingan — pelanggan isi alamat penghantaran + poskod + negeri, kos penghantaran dikira automatik ikut zon (Semenanjung vs Sabah/Sarawak/Labuan, kadar boleh ubah di jadual `zon_penghantaran`). Pesanan masuk ke jadual `pesanan_edagang` (belum ada paparan dalam apps lagi — sila semak terus di Supabase Table Editor buat masa ini).

**Had Fasa 1 (sengaja, bukan bug):**
- Bayaran hanya **Online Transfer manual** (sama seperti pre-order kedai) — belum ada payment gateway (Billplz/SenangPay).
- Kos penghantaran guna **kadar sebenar EasyParcel** (ikut berat & alamat) bila EasyParcel disambung & alamat pengambilan diisi (Fasa 3b — lihat bahagian "🚚 Kadar Sebenar & Label EasyParcel" di bawah); jatuh balik ke kadar flat ikut zon jika EasyParcel tak dapat dihubungi.
- ~~Tiada paparan pesanan e-dagang dalam `pengurusan.html`~~ — **sudah ditambah**: tab **Tempahan → 🛒 E-Dagang** papar semua pesanan dengan butiran penuh, status bayaran/pesanan boleh dikemaskini, kurier/no. tracking boleh diisi, dan bukti bayaran boleh dilihat terus.

**Akaun Pelanggan (optional):** Butang "👤 Akaun Saya" di header benarkan pelanggan daftar/log masuk untuk simpan alamat & lihat sejarah pesanan — guest checkout (tanpa akaun) tetap berfungsi sepenuhnya untuk yang tak mahu daftar.

> ⚠️ Jika pelanggan baru daftar tapi tak boleh terus log masuk selepas "Daftar" (kekal di skrin log masuk), sebabnya sama seperti isu akaun pekerja: Supabase perlukan pengesahan e-mel dahulu. Jika mahu pelanggan terus boleh belanja lepas daftar (tanpa perlu sahkan e-mel), pergi ke Supabase → **Authentication → Providers → Email** dan matikan "Confirm email".

### 🚚 Sambung EasyParcel (Fasa 3a — sambungan OAuth sahaja)
Di **Profile**, kad "🚚 EasyParcel" benarkan pemilik sambungkan akaun EasyParcel (guna OAuth 2.0 — anda log masuk & benarkan akses terus di laman EasyParcel, bukan taip password di sini). Buat masa ini, sambungan ini **cuma simpan token akses** — kadar penghantaran sebenar & jana label automatik akan disambung dalam fasa seterusnya.

> 🔒 `client_secret` EasyParcel **TIDAK PERNAH** masuk ke kod client-side — ia disimpan sebagai *secret* Edge Function sahaja (lihat langkah deploy di bawah), dan token akses/refresh disimpan dalam jadual `easyparcel_auth` yang **tertutup sepenuhnya** dari client (tiada sesiapa, termasuk pemilik log masuk, boleh baca token mentah melalui apps — hanya Edge Function guna kunci admin boleh akses).

**Deploy Edge Function (buat SEKALI sahaja):**
1. Daftar app di [developer.easyparcel.com](https://developer.easyparcel.com) jika belum, salin **Client ID** dan **Client Secret**
2. Daftarkan **Redirect URI** app tersebut kepada:
   ```
   https://smepriytkoxkmpvjvvzq.supabase.co/functions/v1/easyparcel-oauth-callback
   ```
3. Buka Command Prompt/Terminal, masuk ke folder `wafi-app`
4. Log masuk & pautkan CLI (skip jika dah buat untuk fungsi lain sebelum ini):
   ```
   npx supabase login
   npx supabase link --project-ref smepriytkoxkmpvjvvzq
   ```
5. Tetapkan secret (client_secret **TIDAK BOLEH** masuk kod, letak di sini sahaja):
   ```
   npx supabase secrets set EASYPARCEL_CLIENT_ID=d49fd1b6-16d3-445f-b912-56b011c85b23
   npx supabase secrets set EASYPARCEL_CLIENT_SECRET=<client secret sebenar anda>
   ```
6. Deploy fungsi — **PENTING**: kena guna `--no-verify-jwt` sebab EasyParcel redirect terus browser ke sini (bukan panggilan dari kod app dengan token log masuk):
   ```
   npx supabase functions deploy easyparcel-oauth-callback --no-verify-jwt
   ```
7. Selesai — kembali ke **Profile → EasyParcel**, tekan "🔗 Sambung EasyParcel", log masuk ke akaun EasyParcel anda & benarkan akses. Anda akan dibawa balik ke apps dengan status "✅ Disambungkan".

### 🚚 Kadar Sebenar & Label EasyParcel (Fasa 3b)
Selepas EasyParcel disambung (Fasa 3a di atas) dan `SQL_TAMBAHAN_14.sql` dijalankan, laman e-dagang boleh papar **kadar penghantaran sebenar** ikut kurier (bukan lagi kadar flat), dan pemilik/pekerja boleh **jana label & no. AWB terus** dari `pengurusan.html` — tiada lagi salin-tampel manual ke laman EasyParcel.

**Langkah setup:**
1. Di **Profile → EasyParcel**, isi & simpan **"📍 Alamat Pengambilan (Pickup)"** — ini alamat kedai/gudang yang EasyParcel akan jemput bungkusan. Wajib diisi sebelum kadar sebenar/label boleh berfungsi.
2. (Optional tapi disarankan) Kemaskini **berat (kg)** setiap produk di **Stok** — lalai 0.5kg jika tak diisi. Berat digunakan untuk kira kos penghantaran yang tepat.
3. Deploy 3 Edge Function baru (sekali sahaja, dari folder `wafi-app`):
   ```
   npx supabase functions deploy easyparcel-quotation
   npx supabase functions deploy easyparcel-book-shipment
   npx supabase functions deploy easyparcel-wallet-balance
   ```
   (Tiada `--no-verify-jwt` untuk mana-mana ini — berbeza dengan `easyparcel-oauth-callback` — sebab kesemuanya dipanggil dari dalam apps dengan token log masuk yang sah.)
4. Selesai. Di laman e-dagang, lepas pelanggan isi poskod & negeri, senarai kurier & harga sebenar akan terpapar untuk dipilih (jatuh balik senyap ke kadar flat jika EasyParcel tak dapat dihubungi — checkout tetap berfungsi). Di **Tempahan → 🛒 E-Dagang**, pesanan yang ada kurier dipilih akan papar butang **"📦 Buat Label EasyParcel"** — tekan untuk jana AWB terus lepas bayaran disahkan. Baki wallet EasyParcel semasa dipaparkan terus di kad **Profile → EasyParcel** (papar amaran jika baki di bawah RM10).

### 💳 Bayaran Online (Billplz) — Fasa 2
Laman e-dagang kini ada 2 kaedah bayar: **"💳 Bayar Online"** (Billplz — FPX/kad, disahkan automatik) dan **"🏦 Transfer Manual"** (kaedah asal, perlu upload bukti). Bayar Online dipilih secara lalai.

**1. Daftar akaun Billplz Sandbox (percuma, serta-merta):**
1. Pergi ke [billplz-sandbox.com](https://www.billplz-sandbox.com) dan daftar akaun.
2. Di dashboard, pergi ke **Settings → API Keys** — salin **Secret Key** dan **X Signature Key**.
3. Pergi ke **Collections → Create Collection**, beri nama (cth: "Wafi Tijarah Trading") — salin **Collection ID** (contoh: `yhx5t1pp`).

> ℹ️ Ini akaun **Sandbox** (ujian, tiada duit sebenar). Apabila sedia untuk terima bayaran sebenar, daftar akaun Production di [billplz.com](https://www.billplz.com), ulang langkah yang sama untuk dapatkan Secret Key/X Signature Key/Collection ID **Production**, kemudian kemaskini secrets (langkah 3 di bawah) — tiada perubahan kod diperlukan, hanya tukar secrets & `BILLPLZ_BASE_URL`.

**2. Jalankan `SQL_TAMBAHAN_16.sql`** di Supabase SQL Editor.

**3. Tetapkan secrets & deploy 2 Edge Function baru** (dari folder `wafi-app`):
```
npx supabase secrets set BILLPLZ_SECRET_KEY=<Secret Key dari dashboard Billplz>
npx supabase secrets set BILLPLZ_X_SIGNATURE_KEY=<X Signature Key dari dashboard Billplz>
npx supabase secrets set BILLPLZ_COLLECTION_ID=<Collection ID dari dashboard Billplz>
npx supabase secrets set BILLPLZ_BASE_URL=https://www.billplz-sandbox.com
npx supabase functions deploy billplz-create-bill
npx supabase functions deploy billplz-webhook --no-verify-jwt
```
> ⚠️ `billplz-webhook` **MESTI** guna `--no-verify-jwt` — Billplz hantar POST terus dari server mereka (bukan panggilan dari app dengan token log masuk), sama seperti `easyparcel-oauth-callback`. Keselamatan callback ini dikawal oleh pengesahan **X-Signature** (HMAC-SHA256) dalam kod, bukan oleh token Supabase.

**4. Selesai.** Test dengan checkout sebenar di laman e-dagang, pilih "Bayar Online" — anda akan dibawa ke halaman Billplz Sandbox untuk simulasi bayaran (FPX simulator disediakan Billplz untuk sandbox, tiada bank sebenar diperlukan). Selepas bayar, anda dibawa balik ke laman dengan status pengesahan **sebenar** (bukan sekadar parameter URL yang boleh dipalsukan) — status disahkan oleh webhook `billplz-webhook` terus dalam pangkalan data.

Bila sedia untuk Production: daftar akaun sebenar, ulang langkah 3 dengan Secret Key/X Signature Key/Collection ID Production dan `BILLPLZ_BASE_URL=https://www.billplz.com`, redeploy kedua-dua fungsi.

### 📡 Kunci Peranti GPS semasa Thumb In
Sebelum ini, jika pekerja buka apps di 2 peranti (cth: telefon utama + telefon simpanan) semasa masih Thumb In, kedua-dua peranti akan sangka mereka belum Thumb In lagi (kerana status disimpan tempatan di setiap peranti) — bila ditekan Thumb In di peranti kedua, ia cipta sesi kehadiran BAHARU, dan kedua-dua peranti hantar titik GPS serentak secara berasingan, mengelirukan jejak/jarak.

Ini telah dibaiki:
- Semakan "adakah saya sudah Thumb In" kini semak terus pada Supabase (bukan storan tempatan peranti sahaja) — peranti kedua akan kesan sesi sedia ada dan sertai sesi yang sama, bukan cipta yang baharu.
- **Hanya SATU peranti** menjadi sumber GPS pada satu-satu masa — peranti yang PERTAMA hantar ping selepas Thumb In. Peranti kedua senyap sahaja (tak hantar GPS) selagi peranti pertama masih aktif.
- Jika peranti pertama berhenti hantar ping selama **lebih 3 minit** (bateri habis, apps ditutup, dsb.), peranti kedua automatik ambil alih sebagai sumber GPS seterusnya.

Tiada tetapan tambahan diperlukan — ciri ini automatik selepas `SQL_TAMBAHAN_21.sql` dijalankan.

### 💳 Kaedah Bayaran di Rekod Baru
Borang **Rekod Baru** (Penghantaran → Rekod Baru) kini ada 3 kaedah bayaran: **💵 Tunai**, **🏦 Transfer** (Online Transfer/QR Instant Transfer), dan **📋 Hutang**. Diskaun % automatik terpakai untuk Tunai & Transfer — menggunakan kadar yang **sama** dengan sistem diskaun pre-order sedia ada (Lebih → Tetapan Pre-Order & Diskaun: "Diskaun COD/Tunai %", "Diskaun Online Transfer %", "Minima Pesanan"), supaya hanya satu tempat perlu diubah jika kadar berubah. Hutang sentiasa 0% diskaun.

Jumlah pada resit akan papar pecahan Subjumlah/Diskaun/Jumlah Akhir bila diskaun terpakai, serta kaedah bayaran yang digunakan.

### 🏪 Bonus Kedai Baru
Bonus ini **TIDAK dibayar semata-mata kerana kedai didaftarkan** — ia hanya sah selepas kedai itu buat **penghantaran/transaksi PERTAMA sebenar** (borang **Hantar**), dan jumlahnya bergantung kaedah bayaran transaksi pertama itu:

- **🚚 Transaksi pertama Tunai atau Transfer** (beli & bayar terus) — bonus penuh terus, default **RM10** (boleh ubah di **Lebih → Tetapan Kos Operasi → "Bonus Kedai Baru — Beli & Bayar"**).
- **🤝 Transaksi pertama Consignment atau 📋 Hutang** — bonus asas lebih rendah dahulu, default **RM2** (boleh ubah di **"Bonus Kedai Baru — Consignment/Hutang"**), sebab hasil jualan sebenar belum pasti/tertangguh.
  - **Top-up automatik**: bila kedai itu KEMUDIAN buat **belian seterusnya secara Tunai/Transfer** (bayar terus buat kali pertama), sistem bayar tambahan (default **RM8**) supaya jumlah keseluruhan bonus kedai tu cecah kadar penuh (RM2+RM8=RM10) — **tak pernah lebih** daripada kadar "Beli & Bayar". Tambahan dikira automatik (`Bayar − Consignment`), jadi kalau kadar tetapan diubah, top-up turut sesuai sendiri.
  - Top-up ini **acara berasingan**, dikreditkan pada **tarikh belian tunai/transfer itu berlaku** (bukan tarikh transaksi pertama) — kalau ia jatuh bulan lain, ia masuk Laporan/Kiraan Upah bulan tersebut, bukan bulan transaksi pertama.
  - Kalau kedai terus consignment/hutang sahaja (tak pernah bayar tunai/transfer), bonus kekal RM2 — tiada top-up dibayar.
- Kedai yang **berdaftar tapi tak pernah bertransaksi langsung TIDAK dapat bonus apa-apa** — elak pekerja daftar kedai "kosong" semata-mata untuk kutip bonus.
- Kalau mana-mana transaksi yang jadi asas bonus (pertama atau top-up) kemudian **dipadam**, sistem automatik kira semula ikut transaksi yang tinggal — tiada rekod "cache" berasingan.

Bonus ini:
- Dipaparkan dalam **Lebih → Kiraan Upah Saya** (pekerja) sebagai baris "Bonus Kedai Baru", termasuk dalam pecahan harian pada tarikh setiap acara bonus (transaksi pertama DAN/ATAU tarikh top-up, jika berkenaan) — walaupun tiada penghantaran lain pada hari tersebut.
- Dipaparkan dalam **Laporan** (pemilik) sebagai sebahagian Kos Operasi, dengan pecahan bilangan kedai unik & jumlah bonus bagi setiap pekerja, pada bulan setiap acara bonus berlaku (bukan bulan kedai didaftarkan).
- **Pekerja hanya boleh daftar kedai baru selepas Thumb In** — ini mengelakkan pendaftaran kedai semasa tidak bertugas. Pemilik tidak tertakluk sekatan ini.
- ⚠️ Bonus ini **belum** ada kategori Baucar Bayaran rasmi tersendiri (setakat ini cuma dipaparkan dalam Laporan/Kiraan Upah, bukan dokumen audit LHDN bernombor siri seperti petrol/upah/makan) — beritahu jika perlu ditambah.

Kedai yang didaftarkan juga dipaparkan nama pekerja pendaftarnya di **Senarai Kedai** (kelihatan untuk akaun pemilik sahaja).

### 🗑️ Pelupusan Stok (Rosak/Expired)
Borang **Rekod Baru** (Penghantaran → Rekod Baru) kini ada pilihan Jenis Rekod ke-3: **🗑️ Rosak/Expired**, khusus untuk pekerja rekod stok bawaan (yang dah diambil dari gudang) yang rosak, tamat tempoh, atau hilang semasa di lapangan.

- Pilih produk & kuantiti seperti biasa, pilih **Sebab** (Rosak / Expired / Hilang / Lain-lain), tiada kedai destinasi atau kaedah bayaran perlu diisi.
- Jumlah dipaparkan sebagai **"Anggaran Kerugian (Modal)"** — dikira ikut harga beli (kos), bukan harga jual, kerana ini kerugian bukan jualan.
- Selepas disahkan, stok bawaan pekerja terus dipotong (tidak dipulangkan ke gudang — barang dianggap musnah).
- Rekod pelupusan dipaparkan sekali dalam **Sejarah** (sub-tab Penghantaran), digabung mengikut tarikh dengan rekod jualan biasa — kad berwarna merah dengan label sebab. Pemilik nampak semua rekod pelupusan semua pekerja (dengan nama pekerja); pekerja hanya nampak rekod sendiri.

Tiada tetapan tambahan diperlukan — ciri ini automatik selepas `SQL_TAMBAHAN_23.sql` dijalankan.

### 🛒 Tugasan Pesanan E-Dagang
Pesanan dari laman e-dagang (`index.html`) kini perlu **ditugaskan kepada pekerja tertentu** oleh pemilik sebelum pekerja itu boleh nampak pesanan tersebut.

- Di **Tempahan → E-Dagang** (pemilik sahaja), setiap kad pesanan ada dropdown **"Belum ditugaskan"** — pilih nama pekerja untuk tugaskan.
- **Jika pemilik tak pilih sesiapa, pesanan itu langsung tak kelihatan** kepada mana-mana pekerja (bukan sekadar tak boleh diambil) — dikuatkuasakan di peringkat pangkalan data (RLS), bukan sekadar disembunyikan di skrin.
- Pekerja yang ditugaskan boleh urus pesanan itu sepenuhnya (kemaskini status, tracking, buat label EasyParcel) sama seperti pemilik, tetapi tak boleh tugaskan semula kepada pekerja lain atau lihat pesanan yang bukan ditugaskan kepada mereka.
- **Upah** dikira automatik sama seperti penghantaran biasa — ikut upah per-produk (medan "Upah Pekerja" pada setiap Stok), dikira sebaik status pesanan bertukar ke **🚚 Dihantar** atau **✓ Selesai**. Dipaparkan dalam Laporan (pemilik) dan Kiraan Upah Saya (pekerja) sebagai baris "Upah E-Dagang", termasuk dalam pecahan harian.

Tiada tetapan tambahan diperlukan — ciri ini automatik selepas `SQL_TAMBAHAN_24.sql` dijalankan.

### 📸 Galeri Gambar Kedai
Borang **Daftar/Kemaskini Kedai** kini ada butang **"📸 Galeri Gambar Kedai"** — snap gambar depan kedai terus dari kamera telefon (atau pilih gambar sedia ada). Gambar disimpan sebagai galeri (senarai, bukan satu gambar sahaja), jadi pekerja boleh terus tambah gambar baharu pada lawatan akan datang — gambar lama tidak ditimpa.

Gambar dipaparkan sebagai deretan kecil pada kad kedai dalam **Senarai Kedai** — klik gambar untuk buka saiz penuh dalam tab baharu.

**Setup wajib sebelum ciri ini berfungsi**: cipta bucket Storage baharu di Supabase Dashboard → Storage → New bucket → nama `kedai-gambar` → **Public bucket: ON**, kemudian jalankan `SQL_TAMBAHAN_26.sql`.

### 🧾 Baucar Bayaran
Setiap bulan, sistem sudah kira secara automatik upah, elaun minyak (petrol) & duit makan setiap pekerja (dipaparkan dalam **Laporan Bulanan**). Ciri ini **memformalkan angka yang sama** menjadi dokumen audit rasmi bernombor siri (cth: `PV-2026-0001`) — bukan pengiraan baharu, sekadar dokumen sokongan untuk tujuan audit LHDN.

- Di **Laporan Bulanan**, tekan **"🧾 Jana Baucar Bulan Ini"** — sistem akan cipta satu baucar bagi setiap pekerja bagi setiap kategori (Petrol/Upah/Duit Makan) yang jumlahnya lebih RM0 pada bulan tersebut. Jana semula pada bulan yang sama akan kemaskini jumlah baucar **draf** sedia ada (bukan cipta pendua), tetapi baucar yang sudah **Diluluskan/Dibayar** dikekalkan tanpa diubah.
- Kad **"🧾 Baucar Bayaran"** (di bawah Laporan) memaparkan senarai baucar ikut bulan — setiap satu boleh: muat naik resit/bukti bayaran (**pilihan sahaja, bukan wajib** — baucar tanpa resit dipaparkan amaran "⚠️ Tiada resit" tetapi tetap boleh diluluskan/dibayar), tukar status (Draf → Diluluskan → Dibayar), dan **cetak** sebagai dokumen rasmi lengkap dengan ruang tandatangan "Disediakan oleh / Diluluskan oleh / Diterima oleh".
- Nombor siri (`PV-<tahun>-<0000>`) dijana secara automatik & selamat daripada pertindihan (guna PostgreSQL sequence), walaupun beberapa baucar dicipta serentak.
- **Baucar kategori Petrol**: bukti sokongan diambil **secara automatik** daripada log perjalanan GPS (tarikh + jarak km setiap hari dalam bulan tersebut, dikira semasa "Jana Baucar Bulan Ini") — **tiada resit manual diperlukan** untuk petrol, kerana jarak GPS itu sendiri ialah rekod objektif yang boleh disemak. Senarai baucar memaparkan "✅ Log perjalanan disertakan (N hari)" bagi baucar petrol, dan cetakan memaparkan jadual harian penuh (Tarikh | Jarak (km) | Jumlah) menggantikan amaran "Tiada resit". Kategori Upah & Duit Makan masih guna resit manual (pilihan) seperti biasa.

**Setup wajib sebelum ciri ini berfungsi**: cipta bucket Storage baharu di Supabase Dashboard → Storage → New bucket → nama `baucar-resit` → **Public bucket: OFF** (data kewangan sensitif), kemudian jalankan `SQL_TAMBAHAN_26.sql` dan `SQL_TAMBAHAN_27.sql` (tambah lajur `butiran` untuk log perjalanan petrol — tiada bucket Storage baharu diperlukan untuk #27).

⚠️ **Nota penting**: Baucar Bayaran ini ialah dokumen dalaman untuk kemudahan audit — ia **bukan** nasihat percukaian rasmi. Sila rujuk akauntan/ejen cukai berdaftar untuk memastikan format & dokumen sokongan yang digunakan memenuhi keperluan LHDN sepenuhnya bagi perniagaan anda.

### 🤝 Consignment — Upah Ikut Jualan Sebenar
Borang **Rekod Baru** (tab Penghantaran) kini ada pilihan kaedah bayaran ke-4: **"🤝 Consignment"** — untuk barang yang diletak di kedai tanpa bayaran serta-merta, kedai hanya bayar **selepas** ia berjaya dijual kepada pelanggan akhir.

- Sebelum ini, upah pekerja dikira **serta-merta** bila penghantaran direkod, tanpa mengira sama ada kedai betul-betul dah jual barang tu. Kini, untuk penghantaran **Consignment sahaja**, upah **tidak** dikira dalam Laporan Bulanan/Kiraan Upah sehingga jualan disahkan.
- Penghantaran consignment yang belum disahkan dipaparkan di **Sejarah** (tab Penghantaran) dengan label ungu "🤝 Consignment — belum disahkan jualan (upah belum dikira)".
- **Pemilik ATAU pekerja yang buat penghantaran asal** boleh sahkan — masukkan kuantiti *sebenar* yang terjual bagi setiap produk (default = kuantiti dihantar, boleh kurangkan jika jualan separa) dan tekan **"✅ Sahkan Jualan"**. Upah hanya dikira untuk kuantiti yang disahkan terjual — baki tak terjual tidak diupah.
- Baki kuantiti tak terjual **tidak** automatik dipulangkan ke stok gudang — pemilik uruskan pelarasan stok fizikal secara berasingan jika perlu.

**Setup wajib sebelum ciri ini berfungsi**: jalankan `SQL_TAMBAHAN_28.sql`. Tiada bucket Storage baharu diperlukan.

### 🎟️ Voucher Diskaun
Kad **"🎟️ Voucher Diskaun"** (Lebih, pemilik sahaja) — jana kod voucher untuk pelanggan storefront `index.html` guna semasa checkout.

- Tekan **"+ Voucher Baru"** — isi Kod (cth `RAYA10`), Jenis Diskaun (Peratus % atau Tetap RM), Nilai, dan pilihan tambahan: Minima Belanja, Had Guna Keseluruhan, Tarikh Luput. Tekan simpan.
- Pelanggan masukkan kod dalam ruangan "Kod Voucher" semasa checkout di `index.html`, tekan **"🎟️ Guna Kod"** — sistem sahkan kod (aktif, belum luput, cukup minima belanja, belum cecah had guna, no. telefon belum guna kod sama) dan papar diskaun terus dalam jumlah akhir.
- **Sekali guna sahaja setiap no. telefon** bagi setiap kod — tak boleh guna kod sama dua kali dengan no. telefon sama.
- Diskaun **disahkan & dikira semula di server** (bukan dipercayai daripada client) semasa pesanan sebenar dihantar — jika kod jadi tak sah antara masa "Guna Kod" ditekan dan pesanan dihantar (cth kod habis had di saat akhir), pesanan akan gagal dengan mesej ralat yang jelas, pelanggan boleh cuba tanpa kod atau kod lain.
- Selepas kod berjaya digunakan, pautan **"ℹ️ T&C"** muncul di sebelah baris "Diskaun Voucher" — pelanggan tekan untuk papar modal **Terma & Syarat** kod tersebut (minima/maksima belanja, tarikh luput, had guna keseluruhan), supaya jelas kenapa/bila kod itu sah.
- Butang ⏸️/▶️ pada senarai voucher untuk nyahaktif/aktifkan semula tanpa padam; butang ✕ untuk padam kekal; butang ✏️ untuk **edit** voucher sedia ada (kod tak boleh ditukar, semua medan lain boleh).
- Ruangan **"Maksima Belanja (RM, optional)"** — had atas nilai belian yang boleh guna kod ini, elak kod digunakan untuk belian bernilai terlalu besar (cth kod promosi kecil disalahguna untuk pesanan borong). Disahkan di server dalam `validasi_baucar()`, sama macam Minima Belanja.
- Tanda kotak **"🚚 Percuma Penghantaran (Free Shipping)"** — bila ditandakan, kos penghantaran untuk pesanan yang guna kod ini akan **diwaive sepenuhnya (RM0.00)**, tak kira zon/kadar kurier. Papar sebagai "PERCUMA" (harga asal dicoret) di checkout `index.html` sebaik kod digunakan, dan disenaraikan dalam modal T&C kod tersebut. **Dikuatkuasakan di server** oleh trigger `validasi_harga_pesanan_edagang` — client tak boleh "curi" free shipping tanpa kod voucher yang sah dan aktif; kos penghantaran ditimpa kepada 0 semasa pesanan disimpan, tak kira apa nilai dihantar dari client.

**Setup wajib sebelum ciri ini berfungsi**: jalankan `SQL_TAMBAHAN_29.sql` (pemasangan asal), `SQL_TAMBAHAN_38.sql` (pembetulan bug padam voucher yang pernah digunakan + lajur Maksima Belanja), `SQL_TAMBAHAN_40.sql` (medan tambahan untuk modal T&C), dan `SQL_TAMBAHAN_43.sql` (lajur & penguatkuasaan Percuma Penghantaran). Tiada bucket Storage baharu diperlukan.

### 📢 Notifikasi Promosi Bergerak (Laman Utama)
Di bawah senarai voucher dalam kad **"🎟️ Voucher Diskaun"** (pengurusan.html), ada ruangan **"📢 Mesej Promosi (Notifikasi Bergerak di Laman Utama)"** — pemilik boleh taip SEBARANG makluman (bukan terhad kepada voucher sahaja, cth promosi am, cuti perayaan, dll.) dan tekan **"💾 Simpan Mesej Promosi"**.

- Mesej yang disimpan terus dipapar di `index.html` (laman utama pelanggan) sebagai notifikasi emas **bergerak dari kanan ke kiri**, sticky di bawah header supaya kekal kelihatan semasa scroll.
- Kosongkan ruangan & tekan simpan untuk **sembunyikan** notifikasi — tiada banner dipapar langsung jika mesej kosong.
- Mesej disimpan dalam lajur `tetapan.promo_mesej` (baris tunggal, sama macam tetapan diskaun/bank) — kemaskini serta-merta tanpa perlu refresh cache atau redeploy apa-apa.

**Setup wajib sebelum ciri ini berfungsi**: jalankan `SQL_TAMBAHAN_35.sql`. Tiada bucket Storage/Edge Function baharu diperlukan.

### 📣 Hebahan WhatsApp (Marketing)
Kad **"📣 Hebahan WhatsApp (Marketing)"** di pengurusan.html (Lebih, pemilik sahaja) — bantu pemilik hantar mesej promosi kepada senarai nombor WhatsApp secara tersusun.

- **Bukan bot/automasi** — sistem cuma jana pautan `wa.me/<nombor>?text=<mesej>` untuk setiap kontak. Bila tekan "Hantar", WhatsApp terbuka dalam tab baharu dengan mesej dah siap ditaip; pemilik SENDIRI yang tekan hantar dalam WhatsApp. Ini elak isu automasi/bot yang melanggar terma WhatsApp.
- **Senarai Nombor**: satu nombor setiap baris (format apa-apa: `0123456789`, `+6012...`, `6012...` semua diterima & dinormalisasi). Letak nama selepas koma untuk personalize (cth `0123456789, Aisyah`). Duplicate & baris tak sah diabaikan automatik.
- **Mesej Hebahan**: guna `{nama}` untuk letak nama automatik, `*bintang*` untuk **bold** dalam WhatsApp. Disyorkan letak ayat "Reply STOP" untuk pilihan berhenti terima hebahan.
- Tekan **"⚡ Jana Batch"** — sistem susun senarai kepada batch 15 nombor. Setiap kontak ada butang "Hantar" (buka WhatsApp + tanda "dihantar") dan boleh undo ("✓ Dihantar" → tekan untuk buka semula).
- Progress (X/Y dihantar) & status setiap batch auto-disimpan ke jadual `wa_hebahan_state` (Supabase, satu baris untuk pemilik) — **boleh tutup & sambung dari peranti/pelayar LAIN** dari nombor terakhir (cth mula di komputer pejabat, sambung di telefon). localStorage kekal sebagai cache/fallback offline sahaja.
- **📂 Batch Tersimpan** (BERBEZA dari "batch 15 nombor" hantaran di atas — ini perpustakaan senarai bernama): isi ruangan **"Nama Batch"** (cth `Promosi Raya Julai`) dan tekan **"💾 Simpan Batch"** untuk simpan senarai nombor + mesej semasa sebagai satu set bernama, boleh dipanggil semula bila-bila. Lain kali ada hebahan, cukup pilih nama batch di dropdown **"📂 Batch Tersimpan"** — senarai nombor & mesej terus dimuatkan, sedia untuk hantar (tak perlu susun/taip semula). Simpan semula dengan nama sama untuk kemaskini (timpa) batch tu. Butang ✕ di sebelah dropdown untuk padam batch dipilih secara kekal.
- ⚠️ **Elak nombor pelanggan sebenar disimpan dalam kod sumber**: senarai nombor SENGAJA tidak "hardcode" dalam fail — ia ditaip/tampal terus dalam apps semasa digunakan, supaya tiada nombor telefon pelanggan tersimpan dalam repo Git (yang boleh terdedah secara awam melalui GitHub Pages). Data di `wa_hebahan_state`/`wa_hebahan_batch` dilindungi RLS (`is_pemilik()` sahaja).
- 💡 Tips dalaman kad ni: habiskan satu batch (15 nombor) dahulu, rehat 15–30 minit sebelum sambung batch seterusnya — elak akaun WhatsApp disekat kerana dianggap spam oleh sistem WhatsApp sendiri.

**Setup wajib sebelum ciri ini berfungsi**: jalankan `SQL_TAMBAHAN_39.sql` (jadual `wa_hebahan_state` untuk sync cloud) dan `SQL_TAMBAHAN_42.sql` (jadual `wa_hebahan_batch` untuk Batch Tersimpan). Tiada bucket Storage/Edge Function/secret baharu diperlukan.

### 👥 Data Pembeli
Kad **"👥 Data Pembeli"** di pengurusan.html (Lebih, pemilik sahaja) — satukan semua pesanan e-dagang (`pesanan_edagang`) ikut nombor telefon supaya pemilik nampak **senarai pelanggan** (bukan senarai pesanan), untuk susulan & marketing.

- Setiap pelanggan tunjuk: nama, telefon, emel, bilangan pesanan, jumlah **dibayar** (hanya kira pesanan `status_bayaran = disahkan`), dan tarikh pesanan terakhir. Disusun ikut jumlah dibayar tertinggi dahulu.
- Ruangan carian untuk tapis ikut nama/telefon.
- Butang **"📋 Salin untuk Hebahan WhatsApp"** — salin senarai (format `telefon, nama`) ke clipboard, terus boleh tampal ke ruangan "Senarai Nombor" di kad Hebahan WhatsApp.
- Butang **"⬇️ Muat Turun CSV"** — muat turun fail CSV (buka dengan Excel/Google Sheets) untuk simpanan rekod.
- Butang **"📧 Emel Pukal ke Semua Pembeli"** — buka modal untuk taip Subjek & Mesej (guna `{nama}` untuk personalize), kemudian hantar **SATU emel pemasaran** kepada semua pelanggan yang ada rekod emel (ikut penapis carian semasa, jika ada). Ada pengesahan (confirm) sebelum hantar sebab tindakan ini terus ke pelanggan sebenar & tak boleh ditarik balik. Guna Edge Function `hantar-emel-pukal` (guna semula secret `RESEND_API_KEY` yang sama dengan "Emel Susulan") — dihantar dalam batch 100 emel setiap panggilan Resend, dengan jeda antara batch untuk elak rate-limit.

**Setup wajib sebelum ciri ini berfungsi**: senarai/CSV/salin berfungsi terus tanpa apa-apa setup. Untuk **"📧 Emel Pukal"**, perlu `RESEND_API_KEY` sudah ditetapkan (lihat bahagian "📧 Susulan Bayaran & Bebas Voucher" di bawah untuk 3 langkah setup Resend) dan deploy fungsi:
```
npx supabase functions deploy hantar-emel-pukal
```

### 🌐 Trafik Website & Google Analytics
Dua lapisan berasingan untuk jawab soalan "berapa ramai orang singgah website kami, dan dari mana (media sosial/direct)?":

**1. Google Analytics 4 (GA4)** — tag `gtag.js` dipasang pada `index.html` & `pesan.html`. Setiap kali pesanan berjaya dibuat (`hantarPesanan()`), event `purchase` dihantar (jumlah RM, produk, kod voucher jika ada). Dalam GA4 dashboard sendiri (analytics.google.com), pergi **Admin → Events**, cari `purchase`, toggle "Mark as key event" supaya ia dikira sebagai conversion rasmi. Measurement ID semasa: `G-V70WHNCLMY` — jika akaun GA bertukar, cari & ganti ID ini di kedua-dua fail (`<script async src="...?id=G-...">` dan `gtag('config', 'G-...')`).

**2. Kad "🌐 Trafik Website"** (tab "📈 Analisis", pengurusan.html, pemilik sahaja) — jejak kunjungan **sendiri** (bukan tarik dari GA) supaya pemilik boleh lihat statistik terus dalam apps tanpa buka Google Analytics:
- Setiap kali `index.html`/`pesan.html` dibuka, satu rekod ringkas disimpan dalam jadual `kunjungan_web` (halaman, saluran, session id rawak) — **tiada nama/telefon/IP disimpan**, hanya cukup untuk statistik agregat.
- **Saluran** dikesan secara automatik: kalau link ada `?utm_source=facebook` (atau `instagram`/`whatsapp`/`tiktok`/`google`), sistem guna itu; kalau tiada, sistem cuba teka dari `document.referrer` (header rujukan pelayar). **Disyorkan** tambah `?utm_source=facebook&utm_campaign=promo_julai` (contoh) pada link yang dikongsi ke media sosial supaya saluran dikesan dengan tepat — referrer selalunya hilang bila link dibuka dari dalam app Facebook/Instagram/WhatsApp.
- Kad papar: Jumlah Kunjungan, Pelawat Unik (ikut session), pecahan ikut saluran (%), dan pecahan ikut halaman (Kedai Online vs Borang Pesan) — boleh tapis ikut julat tarikh.
- Rekod kunjungan boleh **dibaca hanya oleh pemilik** (RLS `is_pemilik()`); sesiapa sahaja (pelawat awam, tanpa log masuk) boleh **tulis** rekod kunjungan (perlu, sebab pelawat belum login).

**Setup wajib**: jalankan `SQL_TAMBAHAN_41.sql` (jadual `kunjungan_web`). GA4 sudah aktif serta-merta (tiada setup tambahan) kecuali jika Measurement ID bertukar.

### 📧 Susulan Bayaran & Bebas Voucher
Pada setiap pesanan e-dagang yang **belum/gagal bayar** (tab Tempahan → E-Dagang), dua butang baharu muncul (pemilik sahaja):

- **"📧 Emel Susulan"** (kalau pesanan ada alamat emel) — hantar emel peringatan kepada pelanggan supaya selesaikan bayaran, termasuk butiran akaun bank (jika kaedah bayaran ialah transfer manual) dan pautan ke kedai online. Guna [Resend](https://resend.com) (percuma sehingga 100 emel/hari & 3000/bulan).
- **"🔓 Bebaskan Voucher"** (kalau pesanan ada kod voucher digunakan) — padam rekod penggunaan voucher untuk pelanggan tu, supaya kod yang sama boleh **diguna semula** pada pesanan kedua kalau pesanan pertama tak jadi dibayar. Pesanan asal tidak berubah, cuma kod voucher jadi bebas semula. Ada pengesahan (confirm) sebelum bertindak — dilakukan **secara manual** oleh pemilik, bukan automatik, supaya voucher tak terlepas tanpa disedari.

**Setup wajib sebelum ciri "Emel Susulan" berfungsi — 3 langkah:**
1. Daftar akaun percuma di [resend.com](https://resend.com).
2. Sahkan domain `wafitijarahtrading.com` di bahagian **Domains** Resend (tambah rekod DNS yang diberikan Resend — TXT/CNAME/MX ikut arahan mereka) supaya emel boleh dihantar dari alamat `no-reply@wafitijarahtrading.com`. Tanpa domain disahkan, Resend akan tolak hantar emel ke alamat pelanggan sebenar.
3. Set secret & deploy (dari folder `wafi-app`):
```
npx supabase secrets set RESEND_API_KEY=<api-key-dari-resend>
npx supabase functions deploy hantar-emel-susulan
```
> Jika emel gagal dihantar, semak log fungsi (`npx supabase functions logs hantar-emel-susulan`) — baris "Resend status: ### body: {...}" tunjuk sebab sebenar (cth domain belum disahkan).

**Setup wajib untuk "Bebaskan Voucher"**: jalankan `SQL_TAMBAHAN_36.sql` (tambah kebenaran padam pada jadual `baucar_guna` — sebelum ini hanya boleh baca).

### 🔁 Susulan Bayaran Automatik (Harian)
Versi automatik bagi ciri "Emel Susulan" di atas — tak perlu pemilik tekan butang setiap hari. Edge Function `susulan-auto-cron` dijadualkan jalan **sekali sehari** (10 pagi waktu Malaysia) melalui `pg_cron`:

- Semak semua pesanan e-dagang **belum bayar** (`status_bayaran = 'menunggu'`) yang ada alamat emel, dan sudah **≥20 jam** sejak susulan terakhir (atau sejak pesanan dibuat, jika belum pernah disusuli).
- Hantar emel susulan (template sama macam "Emel Susulan" manual, termasuk pautan checkout Billplz yang betul) — maksimum **3 kali**.
- Selepas 3 emel dihantar & bayaran masih belum diterima, pesanan **dibatalkan automatik** (`status_pesanan = 'dibatalkan'`). **Data pembeli KEKAL direkod** — baris pesanan TIDAK dipadam, cuma statusnya bertukar (kekal kelihatan dalam "👥 Data Pembeli" & sejarah pesanan). Voucher yang digunakan (jika ada) turut **dibebaskan automatik** supaya pelanggan boleh cuba beli semula guna kod yang sama.
- Pesanan yang dibayar (`status_bayaran = 'disahkan'`) pada bila-bila masa semasa proses ni akan berhenti disusuli secara automatik (semakan `status_bayaran` dibuat setiap kali cron jalan).

> 🐛 **Pembetulan bug (penting)**: Ambang asal ditetapkan **tepat 24 jam**, yang menyebabkan sesetengah pesanan tersekat kekal terlangkau — sebab `susulan_terakhir` disimpan beberapa saat SELEPAS cron mula (kelewatan panggilan Resend semasa memproses pesanan lain dalam gelung), tapi cron hari esok mengira "24 jam lepas" dari masa mula hari itu — yang sentiasa sedikit lebih awal berbanding stem masa tersebut. Ambang kini **20 jam** (bukan 24) — beri ruang toleransi 4 jam supaya turun naik kelewatan tak sebabkan susulan terlepas selama-lamanya.

**Setup wajib — 4 langkah (dari folder `wafi-app`):**
1. Jalankan `SQL_TAMBAHAN_37.sql` (tambah lajur `bilangan_susulan`/`susulan_terakhir` pada `pesanan_edagang`, aktifkan extension `pg_cron` & `pg_net`).
2. Set secret `CRON_SECRET` (rentetan rawak — elak sesiapa panggil fungsi ni terus dari luar tanpa kebenaran) & deploy:
```
npx supabase secrets set CRON_SECRET=<rentetan-rawak-anda>
npx supabase functions deploy susulan-auto-cron --no-verify-jwt
```
3. Jadualkan panggilan harian (jalankan SEKALI di SQL Editor Supabase, gantikan `<CRON_SECRET>` dengan nilai yang sama seperti langkah 2):
```sql
select cron.schedule(
  'susulan-bayaran-harian',
  '0 2 * * *', -- 2am UTC = 10am waktu Malaysia
  $$
  select net.http_post(
    url := 'https://<project-ref>.supabase.co/functions/v1/susulan-auto-cron',
    headers := '{"Content-Type": "application/json", "x-cron-secret": "<CRON_SECRET>"}'::jsonb,
    body := '{}'::jsonb
  );
  $$
);
```
4. Guna semula secret `RESEND_API_KEY` sedia ada (dari ciri "Emel Susulan" manual) — tiada secret emel baharu diperlukan.

> Untuk lihat/urus jadual cron sedia ada: `select * from cron.job;` — untuk padam jadual: `select cron.unschedule('susulan-bayaran-harian');`

### 🔁 Kempen Win-Back Automatik
Kad **"🔁 Kempen Win-Back Automatik"** (Lebih → dekat "👥 Data Pembeli", pemilik sahaja) — hantar emel "kami rindu awak" automatik setiap **Isnin, 11 pagi waktu Malaysia** (melalui `pg_cron`) kepada pelanggan yang **pernah beli** (ada pesanan `status_bayaran = disahkan`) tapi sudah lama tidak beli lagi.

- **⚠️ Dimatikan (OFF) secara default** — pemilik WAJIB tandakan checkbox "Aktifkan Kempen Win-Back Automatik" dan tekan "💾 Simpan Tetapan" dahulu sebelum sebarang emel dihantar. Ini sengaja, supaya tiada emel pemasaran dihantar tanpa kelulusan eksplisit pemilik.
- **Had Hari Tidak Aktif** (default 60) — berapa lama sejak pembelian terakhir sebelum pelanggan dianggap "tak aktif" dan layak terima emel win-back.
- **Cooldown Hantar Semula** (default 90 hari) — elak pelanggan sama terima emel win-back berulang-ulang setiap minggu; sekali dihantar, tak akan dihantar lagi sehingga cooldown tamat.
- **Kod Voucher untuk Disertakan** (optional) — kod voucher sedia ada (buat dahulu di kad "🎟️ Voucher Diskaun") yang akan disebut dalam emel sebagai galakan untuk beli semula. Sistem semak automatik kod tu masih aktif & belum luput sebelum disebut — kalau kod dah luput/dipadam, emel tetap dihantar tanpa sebut kod (bukan ralat).
- Butang **"🔁 Jana Sekarang (Ujian/Manual)"** — jalankan kempen serta-merta tanpa tunggu Isnin (berguna untuk uji atau kempen segera). Guna log masuk pemilik semasa untuk sahkan kebenaran (bukan `CRON_SECRET`).
- **⚠️ Kali pertama diaktifkan**, sistem akan proses SEMUA pelanggan tak aktif yang terkumpul sejak dulu (bukan hanya yang baru jadi tak aktif minggu ni) — mungkin jumlah besar buat pertama kali. Had keselamatan **maksimum 300 emel setiap kali kempen jalan** (yang paling lama tak aktif diutamakan dahulu); baki akan disambung pada jadual mingguan seterusnya.
- **Sejarah Kempen Terkini** — senarai 15 emel win-back terkini yang dihantar, dipaparkan bawah kad (jadual `winback_log`).

**Setup wajib — 3 langkah (dari folder `wafi-app`):**
1. Jalankan `SQL_TAMBAHAN_44.sql` (lajur tetapan win-back pada `tetapan` + jadual `winback_log`).
2. Deploy fungsi (guna semula secret `RESEND_API_KEY` & `CRON_SECRET` sedia ada — tiada secret baharu diperlukan):
```
npx supabase functions deploy winback-auto-cron --no-verify-jwt
```
3. Jadualkan panggilan mingguan (jalankan SEKALI di SQL Editor Supabase, gantikan `<CRON_SECRET>` dengan nilai sama seperti `susulan-bayaran-harian`):
```sql
select cron.schedule(
  'kempen-winback-mingguan',
  '0 3 * * 1', -- 3am UTC Isnin = 11am waktu Malaysia
  $$
  select net.http_post(
    url := 'https://<project-ref>.supabase.co/functions/v1/winback-auto-cron',
    headers := '{"Content-Type": "application/json", "x-cron-secret": "<CRON_SECRET>"}'::jsonb,
    body := '{}'::jsonb
  );
  $$
);
```

### 🐛 Pembetulan Bug — Pre-Order & Padam Transaksi
Dua bug diperbetulkan:

- **Pre-order tak ditanda selesai**: sebelum ini, bila pekerja hantar barang untuk pre-order (dari tab Hantar → Pre-Order), rekod pre-order asal kekal "belum selesai" selama-lamanya walaupun barang dah sampai kedai. Kini `submitHantar()` automatik kemaskini status pre-order tu ke `selesai` sebaik penghantaran berjaya direkod.
- **Stok "hilang" bila padam transaksi**: sebelum ini, memadam rekod transaksi (Tempahan → Transaksi Kedai) hanya buang rekod tanpa pulangkan stok yang telah ditolak semasa penghantaran asal — jadi kuantiti tu hilang terus daripada sistem. Kini padam transaksi guna RPC `padam_transaksi_kedai()` yang **pulangkan stok ke gudang pusat** secara automatik, dan laraskan balik hutang kedai jika transaksi tu berstatus hutang.

**Setup wajib sebelum ciri ini berfungsi**: jalankan `SQL_TAMBAHAN_30.sql`. Tiada bucket Storage baharu diperlukan.

### 📦 Sertai Kami — Servis Marketing
Butang footer **"🤝 Sertai Kami — Servis Marketing"** (dulu "Sertai Ejen") di `index.html` kini borang untuk pembekal produk yang mahu Wafi Tijarah bantu jual/pasarkan produk mereka.

- Medan borang: Nama, No. Telefon, Nama Produk, Harga Jualan, Margin Keuntungan (%), Gambar Produk, Nota.
- Permohonan masuk ke kad **"🤝 Permohonan Masuk"** (Lebih, pemilik sahaja) di bawah tab baharu **"📦 Marketing"** — papar semua butiran produk termasuk gambar, sama seperti tab Ejen/Penghantar sedia ada (tukar status Baru/Dihubungi/Diterima/Ditolak, padam).

**Setup wajib sebelum ciri ini berfungsi**: jalankan `SQL_TAMBAHAN_31.sql`. Tiada bucket Storage baharu diperlukan.

### 🗺️ Route/Laluan Kedai
Tab **Kedai → 📍 Perlu Servis** (kedai lama tak dihantar stok, kini ≥7 hari — dulu 14 hari) kini boleh dikumpul mengikut route/laluan.

- Pemilik tekan **"🗺️ Urus Route"** — cipta route (cth "Route A"), tekan butang bilangan kedai untuk buka senarai semak & pilih kedai mana masuk route tu.
- Dalam senarai "Perlu Servis", kedai dikumpulkan ikut route masing-masing, **disusun automatik ikut jarak GPS berdekatan** (nearest-neighbour) supaya penghantar tak perlu fikir turutan — kedai tanpa route diletak di bawah bahagian "Belum Ada Route".
- Route boleh dipadam bila-bila masa — kedai dalam route tu akan jadi "belum ada route" secara automatik (tak dipadam).

**Setup wajib sebelum ciri ini berfungsi**: jalankan `SQL_TAMBAHAN_32.sql`. Tiada bucket Storage baharu diperlukan.

### 🏷️ Kategori Produk Boleh Edit
Borang Tambah/Edit Produk (tab Stok) — dropdown Kategori kini **boleh diedit** oleh pemilik, bukan senarai tetap dalam kod.

- Tekan **"✏️ Urus Kategori"** di sebelah label Kategori dalam borang produk — tambah kategori baharu atau padam yang tak diperlukan.
- Padam kategori **tak** jejaskan produk sedia ada yang guna label tu (produk kekal, cuma label itu takkan ada dalam senarai pilihan untuk produk baharu).

**Setup wajib sebelum ciri ini berfungsi**: jalankan `SQL_TAMBAHAN_32.sql` (sama fail dengan Route/Laluan di atas).

### 📱 Preview WhatsApp/Gmail untuk Pautan Produk
Sebelum ini, bila pautan produk (`?produk=S009`) dikongsi ke WhatsApp, preview yang keluar generik (bukan gambar/nama/harga produk sebenar) — sebab WhatsApp "baca" pautan tanpa jalankan JavaScript, jadi meta-tag yang diset oleh `index.html` (selepas page dimuatkan) tak pernah nampak oleh WhatsApp.

> ⚠️ **Sejarah percubaan (penting untuk elak ulang kesilapan sama)**:
> 1. Edge Function `produk-preview` cuba KESAN dulu sama ada permintaan datang dari crawler (semak User-Agent) sebelum balas meta-tag. Masalah: senarai UA crawler tak lengkap (Gmail tak sepadan), jadi crawler tak dikenali dapat 302 kosong (tiada meta-tag).
> 2. Dibetulkan supaya `produk-preview` balas meta-tag OG kepada SEMUA permintaan (tiada lagi kesan UA). Tapi preview Gmail **masih gagal** — disiasat lanjut dan didapati **Supabase Edge Functions SENGAJA menukar Content-Type `text/html` kepada `text/plain` untuk permintaan GET** (ciri platform rasmi, bukan pepijat — [rujukan rasmi](https://supabase.com/docs/guides/functions/http-methods)), sebagai langkah keselamatan supaya domain kongsi `*.supabase.co` tak boleh hos kandungan web boleh-laksana (elak phishing/XSS). Crawler ketat macam Gmail tolak baca meta-tag sebab Content-Type salah, walaupun kandungan HTML sebenarnya betul.
> 3. Dicuba juga upload fail HTML statik ke **Supabase Storage** (bukan Edge Function) — tapi Storage **turut** memaksa `text/plain` untuk fail `.html` yang disajikan secara awam (disahkan praktikal, sekatan sama diguna pakai ke seluruh domain `*.supabase.co`, bukan Edge Function sahaja).
>
> **Kesimpulan**: TIADA cara nak sajikan HTML dengan Content-Type betul dari mana-mana URL `*.supabase.co`. Penyelesaian sebenar: jana fail HTML statik dan **commit terus ke GitHub Pages** (domain `wafitijarahtrading.com` sendiri), yang sajikan `.html` dengan Content-Type betul secara semula jadi.

**Penyelesaian akhir**: Edge Function `produk-preview-gen` dipanggil dari `pengurusan.html` setiap kali produk disimpan (`saveStok()`) — ia jana HTML + meta-tag Open Graph sebenar (gambar, nama, harga) dan **commit terus ke repo GitHub** (`biz-free/sistemwafitijarah`, guna GitHub Contents API) di laluan `preview/<kod produk>.html`. GitHub Pages auto-deploy fail tu dalam masa ~30–90 saat, jadi pautan kongsi jadi `https://www.wafitijarahtrading.com/preview/<kod produk>.html` — di domain sendiri, Content-Type betul, berfungsi untuk SEMUA crawler termasuk Gmail. Fail tu sendiri auto-redirect pelawat biasa ke halaman produk sebenar guna `<meta http-equiv="refresh">`.

- Butang **"🔗"** (kongsi) pada setiap produk kini salin pautan dalam format `https://wafitijarahtrading.com/preview/<kod produk>.html`.
- **Setup wajib — 2 langkah:**
  1. Cipta [GitHub Fine-grained Personal Access Token](https://github.com/settings/personal-access-tokens/new) — skop **HANYA** repo `biz-free/sistemwafitijarah`, kebenaran **Repository permissions → Contents → Read and write**. Salin token tu (hanya nampak sekali).
  2. Set sebagai secret Supabase (dari folder `wafi-app`):
```
npx supabase secrets set GITHUB_TOKEN=<token-yang-disalin>
npx supabase functions deploy produk-preview-gen
```
> ⚠️ Produk sedia ada (dicipta sebelum ciri ni wujud) belum ada fail pratonton — edit & simpan semula setiap produk sekali (buka "✏️ Edit" → "Simpan") untuk jana fail pratonton buat kali pertama, atau minta bantuan jana secara pukal.
- Edge Function lama `produk-preview` (dan bucket Storage `produk-preview` yang dicuba sekejap) dibiarkan wujud tapi **tak digunakan lagi** — tak perlu dipadam, tapi boleh diabaikan.
- **Test**: salin pautan kongsi mana-mana produk, tampal di [Facebook Sharing Debugger](https://developers.facebook.com/tools/debug/) untuk lihat preview yang akan keluar (WhatsApp guna enjin crawler serupa Facebook) — patut papar gambar, nama & harga produk sebenar.

**Pendekkan pautan kongsi — DIBUANG**: sebelum ini butang "🔗" cuba pendekkan pautan `produk-preview` guna Edge Function `shorten-link` (proksi ke TinyURL, kemudian dicuba is.gd). **Kedua-duanya menyebabkan preview WhatsApp/Facebook gagal papar** — pemendek percuma memaparkan halaman iklan/confirmation dulu sebelum redirect sebenar, dan crawler WhatsApp (yang tak jalankan JavaScript & tak tunggu) hanya sempat nampak branding generik pemendek tu, bukan meta-tag produk kita. Ciri pemendekan pautan ni dibuang sepenuhnya (`kongsiLinkProduk()` di `index.html` kongsi pautan `produk-preview` terus) supaya preview produk sentiasa betul. Edge Function `shorten-link` kekal wujud (tak dipanggil lagi) — tak perlu dipadam, tapi tak perlu deploy/kemaskini lagi.

### 🛍️ Kemaskini Borang Pesan (pesan.html)
Borang repeat-order kedai runcit (`pesan.html`) dikemaskini dengan 3 perkara:

1. **Kategori produk** — cip kategori ("Semua", "Minuman", dll., ikut kategori sedia ada dalam Stok) di atas grid produk untuk kedai tapis dengan mudah.
2. **Susun semula 2-halaman** — Halaman 1 (Pilih Barang) dan Halaman 2 (Kaedah Bayaran + Maklumat Kedai) kini berasingan, dengan bar troli di bawah memaparkan butang **"CHECKOUT ➜"** untuk teruskan, sama seperti `index.html`.
3. **Kaedah bayaran "💳 Bayar Online"** — Billplz automatik (FPX/kad), sama seperti `index.html`. Kedai runcit dibawa terus ke halaman bayaran Billplz selepas hantar pesanan, status disahkan automatik melalui webhook.

**Setup wajib sebelum "Bayar Online" berfungsi**:
1. Jalankan `SQL_TAMBAHAN_33.sql` (tambah lajur `billplz_bill_id`/`status_bayaran` pada `pre_order`, kemaskini fungsi `semak_status_pesanan` supaya sokong kedua-dua jadual pesanan).
2. **Deploy semula** 2 Edge Function sedia ada (kini sokong `pesanan_edagang` DAN `pre_order`):
```
npx supabase functions deploy billplz-create-bill
npx supabase functions deploy billplz-webhook --no-verify-jwt
```
Tiada secrets baharu diperlukan — guna terus `BILLPLZ_SECRET_KEY`/`BILLPLZ_X_SIGNATURE_KEY`/`BILLPLZ_COLLECTION_ID` yang sedia ada untuk `index.html`.

### 📦 Jejak Pesanan
Ikon **"📦"** baharu di header `index.html` (sebelah kiri ikon troli 🛒) — pelanggan masukkan **nombor pesanan sahaja** (cth `ED12345678`) untuk lihat status pesanan, status bayaran, senarai barang, jumlah, dan **status tracking kurier** (nama kurier, no. tracking, pautan terus ke laman kurier) sekiranya label EasyParcel sudah dijana.

- Fungsi ni **sengaja tak pulangkan** nombor telefon, e-mel, atau alamat pelanggan — sama seperti had privasi `semak_status_pesanan` sedia ada — jadi selamat untuk sesiapa cuba nombor pesanan (tiada maklumat peribadi terdedah, cuma status).
- Berfungsi untuk pesanan dari `index.html` (pesanan_edagang) sahaja — pesanan dari `pesan.html` (kedai runcit) tak guna kurier automatik, jadi tak relevan untuk ciri ni.

**Setup wajib sebelum ciri ini berfungsi**: jalankan `SQL_TAMBAHAN_34.sql`. Tiada bucket Storage/Edge Function baharu diperlukan.

#### 🔴 Status Kurier LIVE (on-demand)
Bila pembeli tekan butang **"🔍 Jejak"**, selain status tersimpan dalam pangkalan data, sistem juga cuba panggil Edge Function `easyparcel-track-order` untuk dapatkan status **terkini terus dari EasyParcel** (bukan status "beku" yang direkod sekali sahaja semasa label dijana). Jika panggilan berjaya, baris "Status Kurier" bertukar kepada status live; jika gagal (cth kuota API, endpoint tak sepadan, dsb.), baris tu senyap kembali kepada status tersimpan sedia ada tanpa sebarang mesej ralat kepada pembeli — pautan "🔗 Jejak di Laman Kurier" sentiasa tersedia sebagai jalan fallback.

⚠️ **Endpoint status EasyParcel yang digunakan (`shipment/track_orders`) dianggarkan** mengikut corak URL `shipment/submit_orders` yang sudah disahkan berfungsi (Buat Label) — bukan disahkan 100% daripada dokumentasi rasmi. Jika status live tak pernah keluar selepas deploy, semak log fungsi (`npx supabase functions logs easyparcel-track-order`) — baris `EasyParcel track_orders status: ### body: {...}` akan tunjuk respons ralat sebenar EasyParcel untuk laraskan endpoint/parameter yang betul.

```
npx supabase functions deploy easyparcel-track-order
```

**Setup wajib sebelum ciri ini berfungsi**: deploy Edge Function `easyparcel-track-order` (arahan di atas). Guna semula secret `EASYPARCEL_CLIENT_ID`/`EASYPARCEL_CLIENT_SECRET` sedia ada — tiada secret baharu diperlukan.

### 🔍 SEO Laman E-Dagang (index.html)
Laman e-dagang kini ada asas SEO yang lebih lengkap — tiada langkah setup diperlukan, semuanya automatik selepas fail dimuat naik semula.

- **Tajuk, meta description, Open Graph & data struktur (JSON-LD)** ditambah dalam `<head>`, termasuk skema **LocalBusiness** (nama, telefon, e-mel, kawasan liputan) yang sentiasa ada.
- **Pautan produk boleh dikongsi**: setiap kad produk ada butang 🔗 kecil di penjuru atas kanan — tekan untuk salin pautan terus ke produk itu (`?produk=<id>`). Bila pautan itu dibuka, tajuk halaman, meta description & data struktur **Product** (harga, kategori, gambar) akan bertukar automatik ikut produk berkenaan, dan halaman akan scroll terus ke kad produk itu.
- **Data struktur ItemList** turut disuntik merangkumi semua produk dalam katalog, membantu Google fahami keseluruhan katalog daripada satu laman sahaja.
- **`robots.txt`** dan **`sitemap.xml`** baharu ditambah di root — sitemap sengaja hanya senaraikan laman statik (`index.html`, `pesan.html`), bukan setiap produk, kerana produk disimpan dinamik dalam Supabase dan bukan fail statik semasa deploy.
- ⚠️ **Had penting**: tajuk/meta/data struktur di atas dikemaskini melalui JavaScript selepas halaman dimuat. Google memang jalankan JS sebelum mengindeks, jadi ini membantu carian — tetapi crawler pratonton **WhatsApp/Facebook/Telegram tidak jalankan JS**, jadi bila pautan produk dikongsi ke WhatsApp, pratonton yang keluar masih kad umum laman (bukan gambar/harga produk spesifik). Penyelesaian penuh untuk pratonton WhatsApp yang tepat memerlukan server-side rendering atau edge function pengesan bot — di luar skop kerja semasa, boleh dipertimbangkan pada masa hadapan jika diperlukan.

### 🏆 Produk Paling Laris
Kad showcase baharu **"🏆 Produk Paling Laris"** di laman utama `index.html`, dipaparkan di atas katalog penuh (sebelum ruangan carian) — strip boleh-scroll mendatar memaparkan sehingga **8 produk** dengan jualan tertinggi.

- Guna medan `jumlah_terjual` yang sama dengan pilihan susun "🔥 Paling Laris" sedia ada dalam katalog — **automatik**, tiada tetapan pemilik diperlukan.
- Jika tiada produk pernah dijual lagi (`jumlah_terjual = 0` untuk semua), kad ini **tersembunyi automatik** — tak papar showcase kosong.
- Tekan mana-mana kad dalam showcase → halaman scroll terus ke kad penuh produk tu dalam katalog di bawah (turut set semula carian/kategori jika perlu supaya kad tu kelihatan) & disorot sekejap — sama animasi dengan bila pautan produk dikongsi dibuka.
- **Pembetulan bug penting**: `jumlah_terjual` sebelum ini **hanya kira jualan `transaksi`** (penghantaran consignment ke kedai runcit) — jualan e-dagang online sebenar (`pesanan_edagang`) **langsung diabaikan**. Ini bermakna sort "Paling Laris" & showcase baharu ni sebelum pembetulan tak mencerminkan produk yang sebenarnya laku di kalangan pembeli online. Kini `senarai_produk_awam()` kira **kedua-dua saluran** (consignment + e-dagang yang disahkan bayar) — lebih tepat mencerminkan produk yang benar-benar diminati.

**Setup wajib**: jalankan `SQL_TAMBAHAN_48.sql`. Tiada Edge Function/secret baharu diperlukan.

### 🚚 Penghantaran Percuma (pesan.html) & Permohonan Ejen/Penghantar (index.html)
Laman `pesan.html` (borang repeat-order kedai runcit) ada banner hijau di atas mengumumkan penghantaran percuma ke **Perlis, Kedah, Pulau Pinang & Perak** untuk pesanan bernilai minima tertentu (lalai RM100, boleh ubah di **Lebih → Tetapan Pre-Order & Diskaun → "Minima Penghantaran Percuma"**). Ini sekadar **mesej makluman** — sistem tidak mengenakan sebarang bayaran penghantaran tambahan untuk pesanan bawah minima; ia sekadar memaklumkan kedai untuk hubungi terus jika di bawah nilai tersebut.

Pautan **🤝 Sertai Ejen** dan **🛵 Sertai Kami — Kerja Kosong** berada di footer **`index.html`** (laman e-dagang utama), di bawah "Tentang Kami" — bukan di `pesan.html`.
- **Sertai Ejen**: borang permohonan ringkas (nama, telefon, kawasan, nota) untuk individu berminat jadi ejen jualan.
- **Sertai Kami — Kerja Kosong**: borang permohonan penghantar part-time (nama, telefon, kawasan, ada kenderaan sendiri, nota).
- Kedua-dua borang paparkan syarat: komisen/upah dikira ikut kadar sama seperti kadar penghantar barang sedia ada, bayaran melalui transfer bank/QR.

Kedua-dua permohonan boleh diurus di **pengurusan.html → Lebih → 🤝 Permohonan Ejen & Penghantar** (pemilik sahaja) — tapis ikut jenis, kemaskini status (Baru/Dihubungi/Diterima/Ditolak), atau padam. Ini sengaja dibina sebagai **borang tangkap-lead sahaja** — pihak kami tidak membina sistem komisen/operasi ejen automatik memandangkan syarat tersebut (kadar komisen, struktur bayaran, dll) perlu ditentukan oleh pemilik terlebih dahulu; staf akan hubungi pemohon secara manual untuk perbincangan lanjut.

### 🖼️ Gambar Produk & Diskaun Online Transfer
- **Gambar produk**: Bila tambah/edit produk di **Stok**, pemilik boleh muat naik gambar (dipaparkan di borang pre-order supaya kedai nampak produk sebelum order).
- **Diskaun Online Transfer**: Di **Lagi → Tetapan Pre-Order & Diskaun**, pemilik tetapkan minima pesanan (lalai RM500) & peratus diskaun (lalai 5%), serta muat naik gambar QR bank & butiran akaun. Bila kedai buat pre-order melebihi minima DAN pilih "Online Transfer" sebagai kaedah bayar, diskaun terpakai automatik — ini menggalakkan kedai bayar terus (elak hutang) berbanding COD.

**Storage Bucket (perlu dicipta SEKALI sahaja, sebelum jalankan `SQL_TAMBAHAN_4.sql`):**
1. Supabase Dashboard → **Storage** → "New bucket"
2. Nama: `produk-gambar`
3. **Public bucket**: hidupkan (ON) — supaya gambar boleh dipaparkan di borang pre-order awam
4. Klik "Create bucket"
5. Lepas itu, jalankan `SQL_TAMBAHAN_4.sql` di SQL Editor (sertakan dasar akses storan)

### 📊 Status Boleh Edit & Rekod Tepat
Status pre-order (Baru/Diproses/Selesai) kini guna **dropdown** yang boleh ditukar bila-bila masa ke mana-mana arah — elak masalah tertekan status secara tidak sengaja tanpa boleh undo.

### 🎒 Stok Ikut Pekerja
Setiap pekerja perlu **"Ambil Stok"** dari gudang (Hantar → Stok Bawaan Saya) sebelum boleh rekod penghantaran — ini menolak kuantiti dari gudang & tambah ke stok bawaan pekerja tersebut. Rekod Penghantaran kini potong dari **stok bawaan pekerja**, bukan terus dari gudang. Boleh **"Pulangkan Stok"** balik ke gudang jika ada baki tak terjual. Halaman Stok utama terus papar baki **gudang sahaja**.

> ⚠️ Ini perubahan penting: pekerja sedia ada WAJIB "Ambil Stok" dahulu selepas kemaskini ini, jika tidak rekod penghantaran akan gagal ("stok bawaan tidak mencukupi").

### 📍 Jarak Automatik (Auto-GPS)
Input jarak manual dibuang — jarak kini dikira **automatik** dari lokasi GPS pekerja semasa (waktu rekod penghantaran) ke koordinat berdaftar kedai tersebut.

### 🙋 Tugasan Pre-Order (Claim Sistem)
Pre-order baru dari kedai (borang awam/QR) kelihatan kepada **semua pekerja** sehingga seorang pekerja tekan **"🙋 Ambil Tugasan"** — lepas itu, hanya pekerja tersebut (dan pemilik) boleh lihat/urus pre-order itu. First-come-first-served, tiada dua pekerja boleh claim serentak.

### 🗓️ Status Pekerja — Mohon Cuti/MC/Off
Di **Profile**, pekerja boleh mohon Cuti/MC/Tak Jalan (Off) dengan tarikh & nota. Pemilik lulus/tolak di kad "Kelulusan Permohonan Cuti".

### 👤 Profile (dahulu "Lagi")
Tab "Lagi" ditukar nama kepada **Profile** — kini termasuk kemaskini nama/no. telefon sendiri, tukar kata laluan, kiraan upah peribadi (untuk pekerja), dan permohonan cuti.

### 💰 Pecahan Upah Ikut Pekerja
Laporan Bulanan (pemilik) kini tunjuk pecahan upah **ikut setiap pekerja** berasingan (bukan jumlah gabungan sahaja) — memandangkan setiap pekerja hantar kuantiti berbeza, upah masing-masing pun berbeza.

### 🎉 Banner Promosi Bergerak (Pre-Order)
`pesan.html` kini ada banner emas bergerak dari kiri ke kanan (sticky, kekal kelihatan semasa scroll pilih produk) mempromosikan diskaun Online Transfer secara dinamik ikut tetapan semasa.

### 📎 Bukti Bayaran Transfer
Bila kedai pilih "Online Transfer" di borang pre-order, mereka kena isi tarikh & masa transaksi serta muat naik screenshot bukti pindahan — disimpan di bucket **sulit** (`bukti-bayaran`, bukan public) supaya hanya staff log masuk boleh lihat (butang "📎 Lihat Bukti Bayaran" di tab Pre-Order).

**Storage Bucket kedua (sebelum jalankan `SQL_TAMBAHAN_5.sql`):**
1. Storage → "New bucket" → Nama: `bukti-bayaran`
2. **Public bucket**: **JANGAN hidupkan (OFF)** — ini data kewangan sensitif
3. Klik "Create bucket", kemudian jalankan `SQL_TAMBAHAN_5.sql`

### 🧾 Resit Saiz B5
Cetak & PDF resit kini tetap pada saiz kertas **B5** sahaja. Nama fail PDF turut diformat: `{no resit}-{nama kedai}-RM{jumlah}.pdf`.

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
- Ketiga-tiga fail **`index.html`** (laman e-dagang), **`pengurusan.html`** (sistem pengurusan) dan **`pesan.html`** (repeat-order kedai) ada credentials Supabase sendiri — perlu kemas kini **SEMUA fail**.
- Dalam setiap fail, cari baris ini (dekat permulaan `<script>`):
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

### 🔔 Notifikasi Tolak (Web Push)

Tambahan kepada emel invois lewat bayar (`notifikasi-invois-lewat-cron`) — pekerja/pemilik boleh terima makluman TERUS di telefon/browser mereka. Ciri ini **pilihan** (opt-in setiap peranti) — kalau setup di bawah belum dibuat, sistem tetap berjalan seperti biasa (emel sahaja, push dilangkau senyap).

**Setup (sekali sahaja, di projek Supabase anda):**
1. Set secret `VAPID_PRIVATE_KEY` (kunci peribadi VAPID — JANGAN kongsi/commit nilai ini ke git):
```
npx supabase secrets set VAPID_PRIVATE_KEY=<kunci-peribadi-vapid-anda>
```
2. Deploy semula fungsi (guna semula secret `RESEND_API_KEY` & `CRON_SECRET` sedia ada — tiada jadual `pg_cron` baharu diperlukan, cron `notifikasi-invois-lewat-harian` sedia ada terus hantar push sekali secret di atas ditetapkan):
```
npx supabase functions deploy notifikasi-invois-lewat-cron
```
3. Setiap pekerja/pemilik yang mahu terima notifikasi tolak perlu **aktifkan sendiri** di peranti masing-masing: buka `pengurusan.html` → tab **Lebih** → kad "👤 Profil Saya" → tekan **"🔔 Aktifkan Notifikasi Tolak"** → benarkan kebenaran notifikasi bila diminta. Perlu diaktifkan berasingan pada setiap telefon/browser yang digunakan.
4. **iOS (iPhone/iPad)**: notifikasi tolak Web Push hanya berfungsi jika apl ditambah ke **Skrin Utama** ("Add to Home Screen") dahulu — TIDAK berfungsi sekadar dibuka dalam tab Safari biasa. Perlu iOS 16.4 ke atas.

Kunci awam VAPID (selamat didedahkan, bukan rahsia) sudah tertanam dalam `pengurusan.html` dan fungsi Edge — tak perlu ditukar melainkan anda jana pasangan kunci VAPID baharu sendiri (kalau buat, kunci awam & peribadi MESTI dikemaskini serentak di kedua-dua tempat).

---

### 🤝 Sistem Affiliate

Akaun affiliate log masuk sendiri guna **Google** (bukan kata laluan ditetapkan pemilik). Ini **wajib** diaktifkan dahulu di Supabase sebelum sesiapa boleh log masuk `affiliate.html` langsung.

**Setup (sekali sahaja):**
1. Pergi **console.cloud.google.com** → pilih/cipta project (boleh guna project sama spt Google Maps API jika sudah ada).
2. **APIs & Services → OAuth consent screen** → lengkapkan (nama apl, emel sokongan) jika belum pernah buat.
3. **APIs & Services → Credentials → Create Credentials → OAuth client ID** → jenis **Web application**.
4. Tambah **Authorized JavaScript origins**: `https://www.wafitijarahtrading.com`
5. Tambah **Authorized redirect URIs**: `https://smepriytkoxkmpvjvvzq.supabase.co/auth/v1/callback` (URL callback rasmi Supabase — WAJIB tepat macam ni).
6. Salin **Client ID** dan **Client Secret** yang dijana.
7. Di **Supabase Dashboard → Authentication → Providers → Google** → aktifkan (ON), tampal Client ID & Client Secret dari langkah 6 → Save.
8. Di **Supabase Dashboard → Authentication → URL Configuration → Redirect URLs** → tambah `https://www.wafitijarahtrading.com/affiliate.html` (kalau tak ditambah, log masuk Google akan gagal/redirect salah tempat).

Selepas setup di atas siap, sesiapa boleh buka `affiliate.html` → "Log Masuk dengan Google" → isi borang permohonan → tunggu kelulusan anda di kad "💰 Sistem Affiliate" (Lebih, pengurusan.html). Semasa meluluskan, anda tetapkan **kod affiliate** (utk pelanggan guna di checkout) dan **kadar komisen/diskaun** — boleh berbeza setiap affiliate.

Cron harian `matangkan-pendapatan-affiliate-harian` (1 pagi waktu Malaysia) automatik tukar status komisen dari "tertunggak" ke "boleh_tuntut" selepas tempoh tahan 14 hari — sudah dijadualkan & aktif, tiada tindakan tambahan diperlukan.

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
