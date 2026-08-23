-- ═══════════════════════════════════════════════════════════
-- SQL TAMBAHAN 110: Langganan Notifikasi Tolak (Web Push) —
-- simpan subscription setiap peranti (endpoint + kunci penyulitan)
-- pekerja/pemilik supaya server boleh hantar notifikasi terus ke
-- telefon (bukan sekadar emel) bila invois melepasi tarikh bayaran.
--
-- Satu pengguna boleh ada BEBERAPA baris (pelbagai peranti/browser).
-- endpoint unik seluruh sistem — 1 endpoint = 1 langganan sebenar
-- pada 1 peranti/browser, upsert bila peranti sama langgan semula.
-- ═══════════════════════════════════════════════════════════

CREATE TABLE push_subscriptions (
  id text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  user_id uuid REFERENCES auth.users(id) NOT NULL DEFAULT auth.uid(),
  endpoint text NOT NULL UNIQUE,
  p256dh text NOT NULL,
  auth_key text NOT NULL,
  user_agent text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_push_subscriptions_user ON push_subscriptions(user_id);

ALTER TABLE push_subscriptions ENABLE ROW LEVEL SECURITY;

-- Pengguna hanya boleh urus (lihat/tambah/padam) langganan peranti dia sendiri.
-- Tiada WITH CHECK berasingan — USING dipakai jugak sbg WITH CHECK bila FOR ALL,
-- padan dgn user_id DEFAULT auth.uid() supaya insert client biasa terus berfungsi.
CREATE POLICY "pengguna urus langganan push sendiri" ON push_subscriptions FOR ALL
  USING (user_id = auth.uid());

-- (Edge function guna service_role key, automatik pintas RLS utk baca SEMUA
-- langganan bila menghantar push — tiada polisi tambahan diperlukan utk itu.)
