-- =====================================================================
-- LocDailyMar TAHAP 23.1 - BATAS LISENSI PADA PROJECT CLOUD TOKO
-- Jalankan di project Supabase APLIKASI/CLOUD setelah seluruh SQL Tahap 22.
-- Server lisensi tetap berada di project Supabase terpisah.
-- =====================================================================

begin;

create table if not exists public.store_license_entitlements(
    network_id uuid primary key references public.store_networks(id) on delete cascade,
    license_reference uuid not null unique,
    plan_code text not null check(plan_code in('WARUNG_KECIL','WARUNG_SEDERHANA','TOKO','LIFETIME')),
    status text not null default 'active' check(status in('active','suspended','expired','revoked')),
    max_devices integer not null check(max_devices>0),
    max_stores integer not null check(max_stores>0),
    is_lifetime boolean not null default false,
    expires_at timestamptz,
    updated_at timestamptz not null default now(),
    note text,
    constraint store_license_entitlements_expiry check(
        (is_lifetime=true and expires_at is null)
        or (is_lifetime=false and expires_at is not null)
    )
);

alter table public.store_license_entitlements enable row level security;
revoke all on public.store_license_entitlements from anon,authenticated;

create or replace function public.ldm_assert_store_entitlement(p_network_id uuid)
returns public.store_license_entitlements
language plpgsql security definer set search_path='' as $$
declare v public.store_license_entitlements%rowtype;
begin
    select * into v from public.store_license_entitlements where network_id=p_network_id for update;
    if not found then raise exception 'LICENSE_ENTITLEMENT_REQUIRED'; end if;
    if not v.is_lifetime and now()>=v.expires_at then
        update public.store_license_entitlements set status='expired',updated_at=now() where network_id=p_network_id;
        raise exception 'LICENSE_EXPIRED';
    end if;
    if v.status='suspended' then raise exception 'LICENSE_SUSPENDED';
    elsif v.status='expired' then raise exception 'LICENSE_EXPIRED';
    elsif v.status='revoked' then raise exception 'LICENSE_REVOKED';
    elsif v.status<>'active' then raise exception 'LICENSE_NOT_ACTIVE'; end if;
    return v;
end;$$;

create or replace function public.ldm_enforce_store_license_limit()
returns trigger language plpgsql security definer set search_path='' as $$
declare v public.store_license_entitlements%rowtype; v_count integer;
begin
    if new.active is not true then return new; end if;
    if tg_op='UPDATE' then
        if old.active is true and new.network_id=old.network_id then return new; end if;
    end if;
    v:=public.ldm_assert_store_entitlement(new.network_id);
    select count(*) into v_count from public.store_network_stores where network_id=new.network_id and active=true;
    if v_count>=v.max_stores then raise exception 'STORE_LIMIT_REACHED: paket % maksimal % toko',v.plan_code,v.max_stores; end if;
    return new;
end;$$;

drop trigger if exists trg_ldm_store_license_limit on public.store_network_stores;
create trigger trg_ldm_store_license_limit before insert or update of active,network_id
on public.store_network_stores for each row execute function public.ldm_enforce_store_license_limit();

create or replace function public.ldm_enforce_device_license_limit()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_network uuid; v public.store_license_entitlements%rowtype; v_count integer; v_already boolean;
begin
    if new.status<>'active' or new.deleted_at is not null then return new; end if;
    if tg_op='UPDATE' then
        if old.status='active' and old.deleted_at is null and old.client_device_id=new.client_device_id then return new; end if;
    end if;
    select network_id into v_network from public.store_network_stores where store_id=new.store_id and active=true limit 1;
    if v_network is null then raise exception 'STORE_NETWORK_REQUIRED'; end if;
    v:=public.ldm_assert_store_entitlement(v_network);
    select exists(
        select 1 from public.devices d join public.store_network_stores sns on sns.store_id=d.store_id and sns.network_id=v_network and sns.active=true
        where d.client_device_id=new.client_device_id and d.status='active' and d.deleted_at is null
    ) into v_already;
    if not v_already then
        select count(distinct d.client_device_id) into v_count
        from public.devices d join public.store_network_stores sns on sns.store_id=d.store_id and sns.network_id=v_network and sns.active=true
        where d.status='active' and d.deleted_at is null;
        if v_count>=v.max_devices then raise exception 'DEVICE_LIMIT_REACHED: paket % maksimal % perangkat',v.plan_code,v.max_devices; end if;
    end if;
    return new;
end;$$;

drop trigger if exists trg_ldm_device_license_limit on public.devices;
create trigger trg_ldm_device_license_limit before insert or update of status,deleted_at,client_device_id,store_id
on public.devices for each row execute function public.ldm_enforce_device_license_limit();

revoke all on function public.ldm_assert_store_entitlement(uuid) from public,anon,authenticated;
revoke all on function public.ldm_enforce_store_license_limit() from public,anon,authenticated;
revoke all on function public.ldm_enforce_device_license_limit() from public,anon,authenticated;

commit;

-- Developer dapat memeriksa entitlement Cloud:
select e.*,n.code network_code,n.name network_name
from public.store_license_entitlements e join public.store_networks n on n.id=e.network_id
order by e.updated_at desc;
