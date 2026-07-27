-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 61: Serahan cash pekerja → pemilik (resit pindahan/
-- bank-in). Pekerja boleh kumpul duit tunai jualan dan serahkan
-- bila-bila masa (tak perlu selesai setiap hari, boleh bawa ke hari
-- lain) — pemilik sahkan/tolak lepas semak resit.
-- ═══════════════════════════════════════════════════════════

CREATE TABLE serahan_cash (
  id text PRIMARY KEY,
  pekerja_id uuid REFERENCES auth.users(id) NOT NULL,
  jumlah numeric NOT NULL CHECK (jumlah > 0),
  resit_url text,
  nota text,
  status text NOT NULL DEFAULT 'menunggu' CHECK (status IN ('menunggu','disahkan','ditolak')),
  disahkan_oleh uuid REFERENCES auth.users(id),
  disahkan_pada timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE serahan_cash ENABLE ROW LEVEL SECURITY;

CREATE POLICY "pekerja hantar serahan cash sendiri" ON serahan_cash FOR INSERT
  WITH CHECK (pekerja_id = auth.uid());
CREATE POLICY "staff lihat serahan cash" ON serahan_cash FOR SELECT
  USING (pekerja_id = auth.uid() OR is_pemilik());
CREATE POLICY "pemilik sahkan serahan cash" ON serahan_cash FOR UPDATE
  USING (is_pemilik());
CREATE POLICY "pemilik padam serahan cash" ON serahan_cash FOR DELETE
  USING (is_pemilik());

-- Storan: bucket persendirian untuk resit pindahan/bank-in (data kewangan sensitif,
-- sama corak seperti baucar-resit/bukti-bayaran).
INSERT INTO storage.buckets (id, name, public) VALUES ('serahan-cash-resit', 'serahan-cash-resit', false)
  ON CONFLICT (id) DO NOTHING;
CREATE POLICY "staff boleh upload resit serahan cash" ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'serahan-cash-resit' AND auth.role() = 'authenticated');
CREATE POLICY "staff boleh lihat resit serahan cash" ON storage.objects FOR SELECT
  USING (bucket_id = 'serahan-cash-resit' AND auth.role() = 'authenticated');
