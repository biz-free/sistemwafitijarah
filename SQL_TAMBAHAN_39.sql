-- SQL_TAMBAHAN_39: Simpan state Hebahan WhatsApp di cloud (bukan localStorage sahaja)
-- supaya pemilik boleh sambung tugasan hantar mesej dari peranti kedua.

CREATE TABLE IF NOT EXISTS wa_hebahan_state (
  id int PRIMARY KEY DEFAULT 1,
  raw text,
  msg text,
  contacts jsonb DEFAULT '[]'::jsonb,
  updated_at timestamptz DEFAULT now(),
  CONSTRAINT satu_baris_sahaja CHECK (id = 1)
);
INSERT INTO wa_hebahan_state (id) VALUES (1) ON CONFLICT (id) DO NOTHING;
ALTER TABLE wa_hebahan_state ENABLE ROW LEVEL SECURITY;
CREATE POLICY "pemilik urus wa_hebahan_state" ON wa_hebahan_state FOR ALL USING (is_pemilik()) WITH CHECK (is_pemilik());
