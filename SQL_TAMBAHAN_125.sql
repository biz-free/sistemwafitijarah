-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 125: Mesej Follow-up WhatsApp (Perlu Servis) — ikut nama
-- pekerja sebenar (singkatan) & boleh diubah format oleh pemilik.
--
-- Lajur `profiles.singkatan` & RPC `kemaskini_profil_sendiri` DAH WUJUD
-- (dibina sesi lepas) — pekerja boleh tetapkan nama panggilan sendiri di
-- "Profil Saya". Migration ni cuma tambah templat mesej Follow-up
-- (tetapan.mesej_followup_servis) yang pemilik boleh ubah, dgn placeholder
-- {nama}/{telefon}/{link_pesan} disalin ikut pekerja yg log masuk semasa
-- klik "Follow-up" di senarai Perlu Servis.
-- ═══════════════════════════════════════════════════════════

ALTER TABLE tetapan ADD COLUMN IF NOT EXISTS mesej_followup_servis text DEFAULT 'Assalamualaikum 😊
Servis mingguan Wafi Tijarah Trading 🛍️

Ada nak tanya produk, tambah stok atau buat repeat order? Boleh terus WhatsApp kami 👍

Selain produk yang biasa anda ambil, kami juga ada pelbagai lagi produk Muslim Bumiputera untuk kegunaan harian & jualan.

📲 {nama}: {telefon}
🏢 Office: 014-636 3831

🔗 Pesan online terus: {link_pesan}

Wafi Tijarah Trading – Produk Muslim Pilihan Kami';
