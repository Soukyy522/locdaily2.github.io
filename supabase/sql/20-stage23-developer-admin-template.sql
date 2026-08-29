-- ================================================================
-- TAHAP 23 - JADIKAN AKUN AUTH ANDA SEBAGAI DEVELOPER LICENSE ADMIN
-- GANTI email di bawah dengan email Auth developer Anda.
-- Jalankan SETELAH 20-stage23-license-billing.sql
-- ================================================================

insert into public.license_developer_admins(user_id)
select u.id
from auth.users u
where lower(u.email)=lower('GANTI_DENGAN_EMAIL_DEVELOPER_ANDA')
on conflict(user_id) do nothing;

-- Verifikasi
select u.email,d.user_id,d.created_at
from public.license_developer_admins d
join auth.users u on u.id=d.user_id
order by d.created_at;
