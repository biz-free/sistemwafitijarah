-- SQL_TAMBAHAN_42: Simpan Batch Hebahan WhatsApp (senarai nombor + mesej
-- bernama, boleh dipilih semula bila-bila untuk buat hebahan berulang) —
-- BERBEZA dari "batch 15 nombor" (WH_BATCH_SIZE) sedia ada, yang cuma
-- pecahan hantaran dalam satu sesi. Ini pula perpustakaan sesi tersimpan.

CREATE TABLE IF NOT EXISTS wa_hebahan_batch (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nama text NOT NULL UNIQUE,
  raw text,
  msg text,
  contacts jsonb DEFAULT '[]'::jsonb,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE wa_hebahan_batch ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "pemilik urus wa_hebahan_batch" ON wa_hebahan_batch;
CREATE POLICY "pemilik urus wa_hebahan_batch" ON wa_hebahan_batch FOR ALL USING (is_pemilik()) WITH CHECK (is_pemilik());
