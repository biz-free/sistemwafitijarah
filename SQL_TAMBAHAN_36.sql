-- SQL_TAMBAHAN_36: Bebaskan Voucher (guna semula) untuk pesanan belum/gagal bayar
-- Pemilik boleh padam rekod baucar_guna supaya pelanggan boleh guna kod voucher
-- yang sama sekali lagi bila pesanan pertama gagal/belum selesai bayar.

CREATE POLICY "pemilik padam baucar_guna" ON baucar_guna FOR DELETE USING (is_pemilik());
