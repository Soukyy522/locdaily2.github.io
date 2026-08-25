-- ================================================================
-- LocDailyMar - Tahap 6
-- TEMPLATE LINK AUTH USER -> PROFILE
--
-- Gunakan template ini untuk Admin/Kasir/Owner tambahan.
--
-- 1. Buat user terlebih dahulu di Supabase Authentication > Users.
-- 2. Ganti USER_EMAIL_HERE.
-- 3. Ganti USERNAME_HERE.
-- 4. Ganti ROLE_HERE menjadi owner / admin / kasir.
-- 5. Jalankan SQL.
--
-- PASSWORD TIDAK DITULIS DI SQL.
-- ================================================================

begin;

do $$
declare
    v_email text := 'USER_EMAIL_HERE';
    v_username text := 'USERNAME_HERE';
    v_role text := lower('ROLE_HERE');

    v_user_id uuid;
    v_store_id uuid;
begin
    if v_email = 'USER_EMAIL_HERE'
       or btrim(v_email) = '' then
        raise exception 'Ganti USER_EMAIL_HERE.';
    end if;

    if v_username = 'USERNAME_HERE'
       or btrim(v_username) = '' then
        raise exception 'Ganti USERNAME_HERE.';
    end if;

    if v_role not in (
        'owner',
        'admin',
        'kasir'
    ) then
        raise exception
            'ROLE_HERE harus owner, admin, atau kasir.';
    end if;

    select u.id
      into v_user_id
    from auth.users u
    where lower(u.email) =
          lower(btrim(v_email))
    limit 1;

    if v_user_id is null then
        raise exception
            'Auth user % tidak ditemukan.',
            v_email;
    end if;

    select s.id
      into v_store_id
    from public.stores s
    where s.code = 'LDM-DEFAULT'
      and s.deleted_at is null
    limit 1;

    if v_store_id is null then
        raise exception
            'Store LDM-DEFAULT tidak ditemukan.';
    end if;

    if exists (
        select 1
        from public.profiles p
        where p.store_id = v_store_id
          and lower(p.username) =
              lower(btrim(v_username))
          and p.id <> v_user_id
          and p.deleted_at is null
    ) then
        raise exception
            'Username % sudah dipakai profile lain.',
            v_username;
    end if;

    insert into public.profiles (
        id,
        store_id,
        username,
        display_name,
        role,
        active,
        deleted_at,
        deleted_by
    )
    values (
        v_user_id,
        v_store_id,
        btrim(v_username),
        btrim(v_username),
        v_role,
        true,
        null,
        null
    )
    on conflict (id)
    do update set
        store_id = excluded.store_id,
        username = excluded.username,
        display_name = excluded.display_name,
        role = excluded.role,
        active = true,
        deleted_at = null,
        deleted_by = null;
end
$$;

commit;

select
    u.email,
    p.id,
    p.username,
    p.role,
    p.active,
    s.code as store_code
from auth.users u
join public.profiles p
  on p.id = u.id
join public.stores s
  on s.id = p.store_id
where lower(u.email) =
      lower('USER_EMAIL_HERE');
