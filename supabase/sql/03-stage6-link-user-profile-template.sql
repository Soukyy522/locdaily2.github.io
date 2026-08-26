begin;

do $$
declare

    v_account record;
    v_user_id uuid;
    v_store_id uuid;

begin

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


    for v_account in

        select *
        from (
            values

                (
                    'rudigamer126@gmail.com',
                    'locdaily',
                    'owner'
                )
                

        ) as daftar(
            email,
            username,
            role
        )

    loop


        if lower(
            btrim(v_account.role)
        ) not in (
            'owner',
            'admin',
            'kasir'
        ) then

            raise exception
                'Role % tidak valid.',
                v_account.role;

        end if;


        select u.id
          into v_user_id
        from auth.users u
        where lower(u.email) =
              lower(
                  btrim(
                      v_account.email
                  )
              )
        limit 1;


        if v_user_id is null then

            raise exception
                'Auth user % tidak ditemukan.',
                v_account.email;

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
            btrim(v_account.username),
            btrim(v_account.username),
            lower(btrim(v_account.role)),
            true,
            null,
            null
        )
        on conflict (id)
        do update set
            store_id =
                excluded.store_id,
            username =
                excluded.username,
            display_name =
                excluded.display_name,
            role =
                excluded.role,
            active =
                true,
            deleted_at =
                null,
            deleted_by =
                null;

    end loop;

end
$$;

commit;
