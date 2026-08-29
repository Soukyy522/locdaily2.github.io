-- LocDailyMar TAHAP 23 - License Authority
-- JALANKAN HANYA pada project Supabase KHUSUS LISENSI milik pengembang.
-- Jangan jalankan pada project database toko pelanggan.

begin;

create extension if not exists pgcrypto;

create table if not exists public.license_plans (
    code text primary key,
    name text not null,
    max_devices integer not null check (max_devices > 0),
    max_stores integer not null check (max_stores > 0),
    offline_grace_days integer not null check (offline_grace_days between 0 and 30),
    is_lifetime boolean not null default false,
    features jsonb not null default '[]'::jsonb check (jsonb_typeof(features) = 'array'),
    active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table if not exists public.licenses (
    id uuid primary key default gen_random_uuid(),
    key_hash text not null unique check (key_hash ~ '^[0-9a-f]{64}$'),
    key_prefix text not null,
    customer_name text not null,
    customer_email text,
    plan_code text not null references public.license_plans(code),
    status text not null default 'active' check (status in ('active','suspended','revoked','expired')),
    starts_at timestamptz not null default now(),
    expires_at timestamptz,
    is_lifetime boolean not null default false,
    is_trial boolean not null default false,
    trial_identity_hash text check (trial_identity_hash is null or trial_identity_hash ~ '^[0-9a-f]{64}$'),
    trial_initial_installation_hash text check (trial_initial_installation_hash is null or trial_initial_installation_hash ~ '^[0-9a-f]{64}$'),
    trial_started_at timestamptz,
    trial_ends_at timestamptz,
    trial_converted_at timestamptz,
    contact_whatsapp text,
    max_devices_override integer check (max_devices_override is null or max_devices_override > 0),
    max_stores_override integer check (max_stores_override is null or max_stores_override > 0),
    note text,
    status_reason text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint licenses_expiry_valid check (
        (is_lifetime = true and expires_at is null)
        or
        (is_lifetime = false and expires_at > starts_at)
    )
);

-- Bagian ini membuat file yang sama aman dijalankan ulang untuk upgrade
-- dari versi awal TAHAP 23 yang masih berisi tiga paket.
alter table public.license_plans
    add column if not exists is_lifetime boolean not null default false;
alter table public.licenses
    add column if not exists is_lifetime boolean not null default false;
alter table public.licenses
    add column if not exists is_trial boolean not null default false;
alter table public.licenses
    add column if not exists trial_identity_hash text;
alter table public.licenses
    add column if not exists trial_initial_installation_hash text;
alter table public.licenses
    add column if not exists trial_started_at timestamptz;
alter table public.licenses
    add column if not exists trial_ends_at timestamptz;
alter table public.licenses
    add column if not exists trial_converted_at timestamptz;
alter table public.licenses
    add column if not exists contact_whatsapp text;
alter table public.licenses alter column expires_at drop not null;
alter table public.licenses drop constraint if exists licenses_check;
alter table public.licenses drop constraint if exists licenses_expiry_valid;
alter table public.licenses add constraint licenses_expiry_valid check (
    (is_lifetime = true and expires_at is null)
    or
    (is_lifetime = false and expires_at > starts_at)
);

create table if not exists public.license_activations (
    id uuid primary key default gen_random_uuid(),
    license_id uuid not null references public.licenses(id) on delete cascade,
    installation_hash text not null check (installation_hash ~ '^[0-9a-f]{64}$'),
    activation_token_hash text not null unique check (activation_token_hash ~ '^[0-9a-f]{64}$'),
    store_ref text not null,
    device_name text,
    platform text,
    app_version text,
    status text not null default 'active' check (status in ('active','deactivated','revoked')),
    first_activated_at timestamptz not null default now(),
    last_validated_at timestamptz not null default now(),
    deactivated_at timestamptz,
    unique (license_id, installation_hash)
);

create table if not exists public.license_validation_events (
    id bigint generated always as identity primary key,
    license_id uuid references public.licenses(id) on delete set null,
    action text not null check (action in ('activate','validate','deactivate','start_trial')),
    outcome text not null check (outcome in ('success','failed','blocked')),
    key_prefix text,
    installation_hash text,
    ip_hash text,
    reason text,
    created_at timestamptz not null default now()
);

create index if not exists license_activations_license_status_idx
    on public.license_activations (license_id, status);
create index if not exists license_activations_store_idx
    on public.license_activations (license_id, store_ref)
    where status = 'active';
create index if not exists license_events_ip_failure_idx
    on public.license_validation_events (ip_hash, created_at desc)
    where outcome in ('failed','blocked');
create index if not exists license_events_created_idx
    on public.license_validation_events (created_at desc);
alter table public.license_validation_events
    drop constraint if exists license_validation_events_action_check;
alter table public.license_validation_events
    add constraint license_validation_events_action_check
    check (action in ('activate','validate','deactivate','start_trial'));
create unique index if not exists licenses_trial_identity_unique_idx
    on public.licenses (trial_identity_hash)
    where trial_identity_hash is not null;
create unique index if not exists licenses_trial_installation_unique_idx
    on public.licenses (trial_initial_installation_hash)
    where trial_initial_installation_hash is not null;
create index if not exists licenses_trial_monitor_idx
    on public.licenses (is_trial, status, trial_ends_at desc)
    where trial_started_at is not null;

insert into public.license_plans
    (code, name, max_devices, max_stores, offline_grace_days, is_lifetime, features)
values
(
    'WARUNG_KECIL', 'Warung Kecil', 1, 1, 1, false,
    '["dashboard","attendance","pos","inventory","stock_card","stock_opname","returns","reports","expenses","shift_closing","eod","backup_restore","app_update","promo_basic"]'::jsonb
),
(
    'WARUNG_SEDERHANA', 'Warung Sederhana', 3, 1, 3, false,
    '["dashboard","attendance","pos","inventory","stock_card","stock_opname","returns","reports","expenses","shift_closing","eod","backup_restore","app_update","promo_basic","promo_advanced","unit_conversion","suppliers","purchase_order","goods_receipt","cloud_accounts","cloud_devices","offline_queue","recovery_center"]'::jsonb
),
(
    'TOKO', 'Toko', 10, 5, 7, false,
    '["dashboard","attendance","pos","inventory","stock_card","stock_opname","returns","reports","expenses","shift_closing","eod","backup_restore","app_update","promo_basic","promo_advanced","unit_conversion","suppliers","purchase_order","goods_receipt","cloud_accounts","cloud_devices","offline_queue","recovery_center","multi_store","stock_transfer","qa_security"]'::jsonb
),
(
    'LIFETIME', 'Lifetime', 15, 8, 14, true,
    '["dashboard","attendance","pos","inventory","stock_card","stock_opname","returns","reports","expenses","shift_closing","eod","backup_restore","app_update","promo_basic","promo_advanced","unit_conversion","suppliers","purchase_order","goods_receipt","cloud_accounts","cloud_devices","offline_queue","recovery_center","multi_store","stock_transfer","qa_security"]'::jsonb
)
on conflict (code) do update set
    name = excluded.name,
    max_devices = excluded.max_devices,
    max_stores = excluded.max_stores,
    offline_grace_days = excluded.offline_grace_days,
    is_lifetime = excluded.is_lifetime,
    features = excluded.features,
    updated_at = now();

update public.licenses
set is_lifetime = true, expires_at = null, updated_at = now()
where plan_code = 'LIFETIME' and (is_lifetime = false or expires_at is not null);

alter table public.license_plans enable row level security;
alter table public.licenses enable row level security;
alter table public.license_activations enable row level security;
alter table public.license_validation_events enable row level security;

revoke all on table public.license_plans from anon, authenticated;
revoke all on table public.licenses from anon, authenticated;
revoke all on table public.license_activations from anon, authenticated;
revoke all on table public.license_validation_events from anon, authenticated;
revoke all on sequence public.license_validation_events_id_seq from anon, authenticated;

create or replace view public.license_trial_monitor
with (security_invoker = true)
as
select
    l.id as license_id,
    l.key_prefix || '…' as license_key_masked,
    l.customer_name,
    l.customer_email,
    l.contact_whatsapp,
    l.status,
    l.trial_started_at,
    l.trial_ends_at,
    l.trial_converted_at,
    case
        when l.trial_converted_at is not null then 'converted'
        when l.status = 'revoked' then 'revoked'
        when now() >= l.trial_ends_at then 'expired'
        else 'active'
    end as trial_state,
    greatest(0, ceil(extract(epoch from (l.trial_ends_at - now())) / 86400.0))::integer as days_remaining,
    count(a.id) filter (where a.status = 'active') as active_devices,
    count(distinct a.store_ref) filter (where a.status = 'active') as active_stores,
    max(a.last_validated_at) as last_seen_at
from public.licenses l
left join public.license_activations a on a.license_id = l.id
where l.trial_started_at is not null
group by l.id;

revoke all on table public.license_trial_monitor from public, anon, authenticated;
grant select on public.license_trial_monitor to service_role;

drop function if exists public.ldm_issue_license(text,text,text,timestamptz,text,integer,integer);

create function public.ldm_issue_license(
    p_customer_name text,
    p_customer_email text,
    p_plan_code text,
    p_expires_at timestamptz,
    p_note text default null,
    p_max_devices_override integer default null,
    p_max_stores_override integer default null
)
returns table (license_id uuid, license_key text, plan_code text, expires_at timestamptz, is_lifetime boolean)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
    v_random text;
    v_key text;
    v_id uuid;
    v_plan public.license_plans%rowtype;
    v_effective_expiry timestamptz;
begin
    if coalesce(trim(p_customer_name), '') = '' then
        raise exception 'CUSTOMER_NAME_REQUIRED';
    end if;
    select * into v_plan
    from public.license_plans p
    where p.code = upper(trim(p_plan_code)) and p.active;
    if not found then
        raise exception 'PLAN_NOT_FOUND_OR_INACTIVE';
    end if;

    if v_plan.is_lifetime then
        v_effective_expiry := null;
    else
        if p_expires_at is null or p_expires_at <= now() then
            raise exception 'EXPIRY_MUST_BE_IN_FUTURE';
        end if;
        v_effective_expiry := p_expires_at;
    end if;

    v_random := upper(encode(gen_random_bytes(16), 'hex'));
    v_key := format(
        'LDM-%s-%s-%s-%s',
        substr(v_random, 1, 8), substr(v_random, 9, 8),
        substr(v_random, 17, 8), substr(v_random, 25, 8)
    );

    insert into public.licenses (
        key_hash, key_prefix, customer_name, customer_email, plan_code,
        expires_at, is_lifetime, note, max_devices_override, max_stores_override
    ) values (
        encode(digest(upper(trim(v_key)), 'sha256'), 'hex'),
        left(v_key, 12), trim(p_customer_name), nullif(lower(trim(p_customer_email)), ''),
        v_plan.code, v_effective_expiry, v_plan.is_lifetime, nullif(trim(p_note), ''),
        p_max_devices_override, p_max_stores_override
    ) returning id into v_id;

    return query select v_id, v_key, v_plan.code, v_effective_expiry, v_plan.is_lifetime;
end;
$$;

drop function if exists public.ldm_start_trial(text,text,text,text,text);

create function public.ldm_start_trial(
    p_customer_name text,
    p_customer_email text,
    p_identity_hash text,
    p_installation_hash text,
    p_whatsapp text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_issued record;
    v_trial_end timestamptz := now() + interval '14 days';
begin
    if coalesce(trim(p_customer_name), '') = '' then
        raise exception 'CUSTOMER_NAME_REQUIRED';
    end if;
    if coalesce(trim(p_customer_email), '') = '' or position('@' in p_customer_email) < 2 then
        raise exception 'CUSTOMER_EMAIL_INVALID';
    end if;
    if p_identity_hash !~ '^[0-9a-f]{64}$' or p_installation_hash !~ '^[0-9a-f]{64}$' then
        raise exception 'TRIAL_IDENTITY_INVALID';
    end if;
    if exists (
        select 1 from public.licenses
        where trial_identity_hash = p_identity_hash
           or trial_initial_installation_hash = p_installation_hash
    ) then
        raise exception 'TRIAL_ALREADY_USED';
    end if;

    select * into v_issued
    from public.ldm_issue_license(
        p_customer_name := trim(p_customer_name),
        p_customer_email := lower(trim(p_customer_email)),
        p_plan_code := 'WARUNG_SEDERHANA',
        p_expires_at := v_trial_end,
        p_note := 'Trial otomatis Warung Sederhana 14 hari',
        p_max_devices_override := 1,
        p_max_stores_override := 1
    );

    update public.licenses
    set is_trial = true,
        trial_identity_hash = p_identity_hash,
        trial_initial_installation_hash = p_installation_hash,
        trial_started_at = now(),
        trial_ends_at = v_trial_end,
        contact_whatsapp = left(nullif(regexp_replace(trim(p_whatsapp), '[^0-9+]', '', 'g'), ''), 24),
        updated_at = now()
    where id = v_issued.license_id;

    return jsonb_build_object(
        'license_id', v_issued.license_id,
        'license_key', v_issued.license_key,
        'plan_code', 'WARUNG_SEDERHANA',
        'trial_started_at', now(),
        'trial_ends_at', v_trial_end,
        'max_devices', 1,
        'max_stores', 1
    );
exception
    when unique_violation then
        raise exception 'TRIAL_ALREADY_USED';
end;
$$;

drop function if exists public.ldm_convert_trial(uuid,text,timestamptz,text);

create function public.ldm_convert_trial(
    p_license_id uuid,
    p_target_plan_code text,
    p_expires_at timestamptz,
    p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_license public.licenses%rowtype;
    v_plan public.license_plans%rowtype;
    v_effective_expiry timestamptz;
begin
    select * into v_license from public.licenses where id = p_license_id for update;
    if not found then raise exception 'LICENSE_NOT_FOUND'; end if;
    if not v_license.is_trial then raise exception 'LICENSE_IS_NOT_TRIAL'; end if;

    select * into v_plan
    from public.license_plans
    where code = upper(trim(p_target_plan_code)) and active;
    if not found then raise exception 'PLAN_NOT_FOUND_OR_INACTIVE'; end if;

    if v_plan.is_lifetime then
        v_effective_expiry := null;
    else
        if p_expires_at is null or p_expires_at <= now() then
            raise exception 'EXPIRY_MUST_BE_IN_FUTURE';
        end if;
        v_effective_expiry := p_expires_at;
    end if;

    update public.licenses
    set plan_code = v_plan.code,
        is_lifetime = v_plan.is_lifetime,
        expires_at = v_effective_expiry,
        is_trial = false,
        trial_converted_at = now(),
        max_devices_override = null,
        max_stores_override = null,
        status = 'active',
        status_reason = 'Trial dikonversi menjadi paket berbayar',
        note = coalesce(nullif(trim(p_note), ''), note),
        updated_at = now()
    where id = p_license_id;

    update public.license_activations
    set status = 'active', deactivated_at = null, last_validated_at = now()
    where license_id = p_license_id and status = 'revoked';

    return jsonb_build_object(
        'ok', true,
        'license_id', p_license_id,
        'plan_code', v_plan.code,
        'is_lifetime', v_plan.is_lifetime,
        'expires_at', v_effective_expiry,
        'converted_at', now()
    );
end;
$$;

drop function if exists public.ldm_renew_license(uuid,timestamptz,text);

create function public.ldm_renew_license(
    p_license_id uuid,
    p_new_expires_at timestamptz,
    p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_license public.licenses%rowtype;
begin
    select * into v_license from public.licenses where id = p_license_id for update;
    if not found then raise exception 'LICENSE_NOT_FOUND'; end if;
    if v_license.is_lifetime then raise exception 'LIFETIME_LICENSE_DOES_NOT_REQUIRE_RENEWAL'; end if;
    if p_new_expires_at is null or p_new_expires_at <= now() then
        raise exception 'EXPIRY_MUST_BE_IN_FUTURE';
    end if;

    update public.licenses
    set expires_at = p_new_expires_at,
        status = 'active',
        status_reason = 'Lisensi diperpanjang',
        note = coalesce(nullif(trim(p_note), ''), note),
        updated_at = now()
    where id = p_license_id;

    update public.license_activations
    set status = 'active', deactivated_at = null, last_validated_at = now()
    where license_id = p_license_id and status = 'revoked';

    return jsonb_build_object(
        'ok', true,
        'license_id', p_license_id,
        'expires_at', p_new_expires_at,
        'status', 'active'
    );
end;
$$;

create or replace function public.ldm_set_license_status(
    p_license_id uuid,
    p_status text,
    p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_status text := lower(trim(p_status));
begin
    if v_status not in ('active','suspended','revoked','expired') then
        raise exception 'INVALID_LICENSE_STATUS';
    end if;

    if v_status = 'expired' and exists (
        select 1 from public.licenses where id = p_license_id and is_lifetime
    ) then
        raise exception 'LIFETIME_LICENSE_CANNOT_EXPIRE';
    end if;

    update public.licenses
    set status = v_status,
        status_reason = nullif(trim(p_reason), ''),
        updated_at = now()
    where id = p_license_id;

    if not found then raise exception 'LICENSE_NOT_FOUND'; end if;

    if v_status in ('revoked','expired') then
        update public.license_activations
        set status = 'revoked', deactivated_at = now()
        where license_id = p_license_id and status = 'active';
    end if;

    return jsonb_build_object('ok', true, 'license_id', p_license_id, 'status', v_status);
end;
$$;

create or replace function public.ldm_license_activate(
    p_key_hash text,
    p_installation_hash text,
    p_activation_token_hash text,
    p_store_ref text,
    p_device_name text,
    p_platform text,
    p_app_version text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_license public.licenses%rowtype;
    v_plan public.license_plans%rowtype;
    v_activation public.license_activations%rowtype;
    v_max_devices integer;
    v_max_stores integer;
    v_device_count integer;
    v_store_count integer;
    v_store_ref text := trim(p_store_ref);
begin
    select * into v_license
    from public.licenses
    where key_hash = lower(trim(p_key_hash))
    for update;

    if not found then raise exception 'LICENSE_KEY_INVALID'; end if;
    perform pg_advisory_xact_lock(hashtextextended(v_license.id::text, 23));

    select * into v_plan from public.license_plans where code = v_license.plan_code and active;
    if not found then raise exception 'PLAN_INACTIVE'; end if;
    if now() < v_license.starts_at then raise exception 'LICENSE_NOT_STARTED'; end if;
    if not v_license.is_lifetime and now() >= v_license.expires_at then
        update public.licenses set status = 'expired', updated_at = now() where id = v_license.id;
        raise exception 'LICENSE_EXPIRED';
    end if;
    if v_license.status <> 'active' then
        raise exception 'LICENSE_NOT_ACTIVE:%', upper(v_license.status);
    end if;
    if length(v_store_ref) < 3 or length(v_store_ref) > 100 then
        raise exception 'STORE_REFERENCE_INVALID';
    end if;

    v_max_devices := coalesce(v_license.max_devices_override, v_plan.max_devices);
    v_max_stores := coalesce(v_license.max_stores_override, v_plan.max_stores);

    select * into v_activation
    from public.license_activations
    where license_id = v_license.id and installation_hash = lower(trim(p_installation_hash))
    for update;

    if found then
        if v_activation.status <> 'active' then
            select count(*) into v_device_count
            from public.license_activations
            where license_id = v_license.id and status = 'active';
            if v_device_count >= v_max_devices then raise exception 'DEVICE_LIMIT_REACHED'; end if;
        end if;

        select count(distinct store_ref) into v_store_count
        from public.license_activations
        where license_id = v_license.id
          and status = 'active'
          and id <> v_activation.id;
        if not exists (
            select 1 from public.license_activations
            where license_id = v_license.id
              and status = 'active'
              and id <> v_activation.id
              and store_ref = v_store_ref
        ) and v_store_count >= v_max_stores then
            raise exception 'STORE_LIMIT_REACHED';
        end if;

        update public.license_activations
        set activation_token_hash = lower(trim(p_activation_token_hash)),
            store_ref = v_store_ref,
            device_name = left(nullif(trim(p_device_name), ''), 120),
            platform = left(nullif(trim(p_platform), ''), 120),
            app_version = left(nullif(trim(p_app_version), ''), 40),
            status = 'active', last_validated_at = now(), deactivated_at = null
        where id = v_activation.id;
    else
        select count(*) into v_device_count
        from public.license_activations
        where license_id = v_license.id and status = 'active';
        if v_device_count >= v_max_devices then raise exception 'DEVICE_LIMIT_REACHED'; end if;

        select count(distinct store_ref) into v_store_count
        from public.license_activations
        where license_id = v_license.id and status = 'active';
        if not exists (
            select 1 from public.license_activations
            where license_id = v_license.id and status = 'active' and store_ref = v_store_ref
        ) and v_store_count >= v_max_stores then
            raise exception 'STORE_LIMIT_REACHED';
        end if;

        insert into public.license_activations (
            license_id, installation_hash, activation_token_hash, store_ref,
            device_name, platform, app_version
        ) values (
            v_license.id, lower(trim(p_installation_hash)), lower(trim(p_activation_token_hash)), v_store_ref,
            left(nullif(trim(p_device_name), ''), 120), left(nullif(trim(p_platform), ''), 120),
            left(nullif(trim(p_app_version), ''), 40)
        );
    end if;

    return jsonb_build_object(
        'license_id', v_license.id,
        'customer_name', v_license.customer_name,
        'plan_code', v_plan.code,
        'plan_name', v_plan.name,
        'features', v_plan.features,
        'max_devices', v_max_devices,
        'max_stores', v_max_stores,
        'offline_grace_days', v_plan.offline_grace_days,
        'is_lifetime', v_license.is_lifetime,
        'is_trial', v_license.is_trial,
        'trial_ends_at', v_license.trial_ends_at,
        'license_expires_at', v_license.expires_at,
        'store_ref', v_store_ref
    );
end;
$$;

create or replace function public.ldm_license_validate(
    p_activation_token_hash text,
    p_installation_hash text,
    p_app_version text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_activation public.license_activations%rowtype;
    v_license public.licenses%rowtype;
    v_plan public.license_plans%rowtype;
begin
    select * into v_activation
    from public.license_activations
    where activation_token_hash = lower(trim(p_activation_token_hash))
      and installation_hash = lower(trim(p_installation_hash))
      and status = 'active'
    for update;
    if not found then raise exception 'ACTIVATION_NOT_FOUND'; end if;

    select * into v_license from public.licenses where id = v_activation.license_id for update;
    select * into v_plan from public.license_plans where code = v_license.plan_code and active;
    if not found then raise exception 'PLAN_INACTIVE'; end if;
    if not v_license.is_lifetime and now() >= v_license.expires_at then
        update public.licenses set status = 'expired', updated_at = now() where id = v_license.id;
        update public.license_activations set status = 'revoked', deactivated_at = now()
        where license_id = v_license.id and status = 'active';
        raise exception 'LICENSE_EXPIRED';
    end if;
    if v_license.status <> 'active' then raise exception 'LICENSE_NOT_ACTIVE:%', upper(v_license.status); end if;

    update public.license_activations
    set last_validated_at = now(), app_version = left(nullif(trim(p_app_version), ''), 40)
    where id = v_activation.id;

    return jsonb_build_object(
        'license_id', v_license.id,
        'customer_name', v_license.customer_name,
        'plan_code', v_plan.code,
        'plan_name', v_plan.name,
        'features', v_plan.features,
        'max_devices', coalesce(v_license.max_devices_override, v_plan.max_devices),
        'max_stores', coalesce(v_license.max_stores_override, v_plan.max_stores),
        'offline_grace_days', v_plan.offline_grace_days,
        'is_lifetime', v_license.is_lifetime,
        'is_trial', v_license.is_trial,
        'trial_ends_at', v_license.trial_ends_at,
        'license_expires_at', v_license.expires_at,
        'store_ref', v_activation.store_ref
    );
end;
$$;

create or replace function public.ldm_license_deactivate(
    p_activation_token_hash text,
    p_installation_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_id uuid;
begin
    update public.license_activations
    set status = 'deactivated', deactivated_at = now(), last_validated_at = now()
    where activation_token_hash = lower(trim(p_activation_token_hash))
      and installation_hash = lower(trim(p_installation_hash))
      and status = 'active'
    returning id into v_id;
    if v_id is null then raise exception 'ACTIVATION_NOT_FOUND'; end if;
    return jsonb_build_object('ok', true, 'activation_id', v_id);
end;
$$;

revoke all on function public.ldm_issue_license(text,text,text,timestamptz,text,integer,integer) from public, anon, authenticated;
revoke all on function public.ldm_start_trial(text,text,text,text,text) from public, anon, authenticated;
revoke all on function public.ldm_convert_trial(uuid,text,timestamptz,text) from public, anon, authenticated;
revoke all on function public.ldm_renew_license(uuid,timestamptz,text) from public, anon, authenticated;
revoke all on function public.ldm_set_license_status(uuid,text,text) from public, anon, authenticated;
revoke all on function public.ldm_license_activate(text,text,text,text,text,text,text) from public, anon, authenticated;
revoke all on function public.ldm_license_validate(text,text,text) from public, anon, authenticated;
revoke all on function public.ldm_license_deactivate(text,text) from public, anon, authenticated;

grant execute on function public.ldm_issue_license(text,text,text,timestamptz,text,integer,integer) to service_role;
grant execute on function public.ldm_start_trial(text,text,text,text,text) to service_role;
grant execute on function public.ldm_convert_trial(uuid,text,timestamptz,text) to service_role;
grant execute on function public.ldm_renew_license(uuid,timestamptz,text) to service_role;
grant execute on function public.ldm_set_license_status(uuid,text,text) to service_role;
grant execute on function public.ldm_license_activate(text,text,text,text,text,text,text) to service_role;
grant execute on function public.ldm_license_validate(text,text,text) to service_role;
grant execute on function public.ldm_license_deactivate(text,text) to service_role;

commit;
