-- 192: Pekerja boleh nampak senarai nama rakan pekerja (untuk Pindah Stok ke Pekerja Lain).
-- Punca bug: RLS profiles hanya benarkan baca profil sendiri, jadi senarai rakan kosong.
-- RPC ini pulangkan id+nama sahaja (tiada data sensitif), pekerja aktif lain.
create or replace function public.senarai_rakan_pekerja()
returns table(id uuid, nama text)
language sql security definer set search_path = public
as $$
  select p.id, p.nama from profiles p
  where p.role = 'pekerja' and p.status = 'aktif' and p.id <> auth.uid()
  order by p.nama;
$$;
revoke all on function public.senarai_rakan_pekerja() from public, anon;
grant execute on function public.senarai_rakan_pekerja() to authenticated;
