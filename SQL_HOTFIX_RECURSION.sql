-- ═══════════════════════════════════════════════════════════
--  WAFI TIJARAH TRADING — HOTFIX: infinite recursion pada profiles
--  JALANKAN SEGERA — bug ini boleh sekat log masuk & urus stok/kedai.
--
--  Punca: dasar "pemilik boleh baca semua profil" / "pemilik boleh
--  daftar profil pekerja" menyemak profiles dengan query terus ke
--  profiles sendiri → Postgres kesan gelung tak berkesudahan.
--  Baiki: guna fungsi SECURITY DEFINER is_pemilik() untuk pintas
--  gelung tersebut (fungsi ini jalan dengan hak lebih tinggi yang
--  tidak tertakluk kepada RLS semasa baca profiles dari dalam).
-- ═══════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "pemilik boleh baca semua profil" ON profiles;
DROP POLICY IF EXISTS "pemilik boleh daftar profil pekerja" ON profiles;

CREATE OR REPLACE FUNCTION is_pemilik() RETURNS boolean
LANGUAGE sql SECURITY DEFINER SET search_path = public STABLE AS $$
  SELECT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'pemilik');
$$;

CREATE POLICY "pemilik boleh baca semua profil" ON profiles FOR SELECT USING (is_pemilik());
CREATE POLICY "pemilik boleh daftar profil pekerja" ON profiles FOR INSERT WITH CHECK (is_pemilik());
