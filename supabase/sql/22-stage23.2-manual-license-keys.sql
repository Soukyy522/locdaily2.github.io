-- ================================================================
-- LocDailyMar - TAHAP 23.2
-- MANUAL LICENSE KEY + FEATURE GATING + FAIL-CLOSED LICENSE GUARD
-- Baseline: TAHAP 23.1
--
-- Jalankan SETELAH SQL Tahap 23 dan 23.1.
-- ================================================================

begin;

create extension if not exists pgcrypto with schema extensions;

-- ------------------------------------------------
-- 1) Feature matrix per paket
-- ------------------------------------------------
alter table public.license_plans
add column if not exists feature_codes text[] not null default '{}'::text[];

update public.license_plans
set
    name = 'Warung Kecil',
    description = 'Paket dasar untuk operasional satu warung dengan POS, barang, laporan, absensi, akun cloud, dan perangkat.',
    monthly_price = 29000,
    yearly_price = 299000,
    lifetime_price = null,
    max_devices = 2,
    max_stores = 1,
    trial_days = 0,
    trial_enabled = false,
    feature_codes = array[
        'core_pos',
        'account_device'
    ]::text[],
    active = true,
    sort_order = 10,
    updated_at = now()
where code = 'warung-kecil';

update public.license_plans
set
    name = 'Warung Sederhana',
    description = 'Untuk usaha kecil yang mulai memakai retur, stock opname, supplier, pengeluaran, backup, serta lebih dari satu toko.',
    monthly_price = 59000,
    yearly_price = 599000,
    lifetime_price = null,
    max_devices = 4,
    max_stores = 2,
    trial_days = 14,
    trial_enabled = true,
    feature_codes = array[
        'core_pos',
        'account_device',
        'returns',
        'stock_opname',
        'expenses',
        'backup_restore',
        'supplier',
        'multi_store'
    ]::text[],
    active = true,
    sort_order = 20,
    updated_at = now()
where code = 'warung-sederhana';

update public.license_plans
set
    name = 'Toko',
    description = 'Paket operasional lengkap untuk toko berkembang dengan procurement, closing/EOD, recovery, PWA/offline, dan cloud control.',
    monthly_price = 99000,
    yearly_price = 999000,
    lifetime_price = null,
    max_devices = 8,
    max_stores = 4,
    trial_days = 0,
    trial_enabled = false,
    feature_codes = array[
        'core_pos',
        'account_device',
        'returns',
        'stock_opname',
        'expenses',
        'backup_restore',
        'supplier',
        'multi_store',
        'procurement',
        'closing_eod',
        'recovery',
        'pwa_offline',
        'cloud_control'
    ]::text[],
    active = true,
    sort_order = 30,
    updated_at = now()
where code = 'toko';

update public.license_plans
set
    name = 'Lifetime',
    description = 'Bayar sekali untuk seluruh fitur paket standar LocDailyMar dengan kuota tertinggi.',
    monthly_price = null,
    yearly_price = null,
    lifetime_price = 2799000,
    max_devices = 15,
    max_stores = 8,
    trial_days = 0,
    trial_enabled = false,
    feature_codes = array[
        'core_pos',
        'account_device',
        'returns',
        'stock_opname',
        'expenses',
        'backup_restore',
        'supplier',
        'multi_store',
        'procurement',
        'closing_eod',
        'recovery',
        'pwa_offline',
        'cloud_control'
    ]::text[],
    active = true,
    sort_order = 40,
    updated_at = now()
where code = 'lifetime';

-- Return type berubah karena ada feature_codes, jadi function lama di-drop.
drop function if exists public.ldm_license_plans();

create function public.ldm_license_plans()
returns table(
    id uuid,
    code text,
    name text,
    description text,
    monthly_price bigint,
    yearly_price bigint,
    lifetime_price bigint,
    max_devices integer,
    max_stores integer,
    trial_days integer,
    trial_enabled boolean,
    feature_codes text[]
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
    select
        p.id,
        p.code,
        p.name,
        p.description,
        p.monthly_price,
        p.yearly_price,
        p.lifetime_price,
        p.max_devices,
        p.max_stores,
        p.trial_days,
        p.trial_enabled,
        p.feature_codes
    from public.license_plans p
    where p.active = true
    order by p.sort_order, p.name;
$$;

revoke all on function public.ldm_license_plans() from public, anon;
grant execute on function public.ldm_license_plans() to authenticated;

-- ------------------------------------------------
-- 2) Manual activation keys
-- Raw license key TIDAK disimpan. Database hanya menyimpan SHA-256 hash.
-- Raw key hanya dikembalikan satu kali saat Developer membuat key.
-- ------------------------------------------------
create table if not exists public.license_activation_keys (
    id uuid primary key default gen_random_uuid(),
    network_id uuid not null
        references public.store_networks(id)
        on delete restrict,
    owner_user_id uuid not null
        references auth.users(id)
        on delete restrict,
    plan_id uuid not null
        references public.license_plans(id)
        on delete restrict,
    billing_cycle text not null
        check (billing_cycle in ('monthly','yearly','lifetime')),
    source_payment_id uuid
        references public.license_payments(id)
        on delete set null,
    key_hash text not null unique,
    key_hint text not null,
    status text not null default 'issued'
        check (status in ('issued','activated','revoked','expired')),
    issue_note text,
    issued_by uuid not null
        references auth.users(id)
        on delete restrict,
    issued_at timestamptz not null default now(),
    activated_at timestamptz,
    activated_by uuid references auth.users(id) on delete set null,
    revoked_at timestamptz,
    revoked_by uuid references auth.users(id) on delete set null,
    revoke_reason text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index if not exists license_activation_keys_network_idx
on public.license_activation_keys(network_id, issued_at desc);

create index if not exists license_activation_keys_payment_idx
on public.license_activation_keys(source_payment_id, issued_at desc)
where source_payment_id is not null;

create unique index if not exists license_one_issued_key_per_payment
on public.license_activation_keys(source_payment_id)
where source_payment_id is not null
  and status = 'issued';

drop trigger if exists trg_license_activation_keys_touch
on public.license_activation_keys;

create trigger trg_license_activation_keys_touch
before update on public.license_activation_keys
for each row execute function public.ldm_touch_row();

alter table public.license_activation_keys enable row level security;
revoke all on public.license_activation_keys from anon, authenticated;

-- ------------------------------------------------
-- 3) Context license: sekaligus melakukan lazy expiry.
-- Begitu halaman mengecek lisensi setelah valid_until lewat,
-- status menjadi expired dan aplikasi dikunci sampai renewal.
-- Lifetime valid_until = NULL dan tidak expire.
-- ------------------------------------------------
create or replace function public.ldm_license_context()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_network uuid;
    v_store uuid;
    v_license public.network_licenses%rowtype;
    v_plan public.license_plans%rowtype;
    v_stores integer := 0;
    v_devices integer := 0;
    v_valid boolean := false;
    v_dev boolean := false;
    v_days integer := null;
    v_network_code text;
    v_network_name text;
    v_store_code text;
    v_store_name text;
begin
    if auth.uid() is null then
        raise exception 'Auth session missing!';
    end if;

    v_store := public.ldm_current_store_id();
    v_network := public.ldm_current_network_id();

    if v_store is null then
        raise exception 'Store aktif belum tersedia.';
    end if;

    if v_network is null then
        raise exception 'Network toko aktif belum tersedia.';
    end if;

    v_dev := public.ldm_is_license_developer();

    select n.code, n.name
      into v_network_code, v_network_name
    from public.store_networks n
    where n.id = v_network
    limit 1;

    select s.code, s.name
      into v_store_code, v_store_name
    from public.stores s
    where s.id = v_store
    limit 1;

    -- Trial yang waktunya habis ditandai expired.
    update public.license_trials t
       set status = 'expired',
           updated_at = now()
     where t.network_id = v_network
       and t.status = 'active'
       and t.expires_at <= now();

    -- Lisensi periodik/trial yang habis menjadi expired.
    update public.network_licenses nl
       set status = 'expired',
           updated_at = now()
     where nl.network_id = v_network
       and nl.status in ('trialing','active')
       and nl.valid_until is not null
       and nl.valid_until <= now();

    select count(*)::int
      into v_stores
    from public.store_network_stores sns
    where sns.network_id = v_network
      and sns.active = true;

    select count(distinct d.client_device_id)::int
      into v_devices
    from public.devices d
    join public.store_network_stores sns
      on sns.store_id = d.store_id
     and sns.active = true
    where sns.network_id = v_network
      and d.status = 'active'
      and d.deleted_at is null;

    if v_dev then
        return jsonb_build_object(
            'network_id', v_network,
            'network_code', v_network_code,
            'network_name', v_network_name,
            'store_id', v_store,
            'store_code', v_store_code,
            'store_name', v_store_name,
            'developer_admin', true,
            'valid', true,
            'status', 'developer',
            'billing_cycle', 'developer',
            'license_code', 'DEVELOPER',
            'plan_code', 'developer',
            'plan_name', 'Developer Override',
            'features', array['*']::text[],
            'max_devices', 999,
            'max_stores', 999,
            'used_devices', v_devices,
            'used_stores', v_stores,
            'over_limit', false,
            'valid_from', null,
            'valid_until', null,
            'days_remaining', null
        );
    end if;

    select *
      into v_license
    from public.network_licenses nl
    where nl.network_id = v_network
    limit 1;

    if v_license.id is not null then
        select *
          into v_plan
        from public.license_plans p
        where p.id = v_license.plan_id
        limit 1;

        v_valid :=
            v_license.status in ('trialing','active')
            and (
                v_license.valid_until is null
                or v_license.valid_until > now()
            );

        if v_license.valid_until is not null then
            v_days := greatest(
                0,
                ceil(
                    extract(epoch from (v_license.valid_until - now()))
                    / 86400.0
                )::int
            );
        end if;
    end if;

    return jsonb_build_object(
        'network_id', v_network,
        'network_code', v_network_code,
        'network_name', v_network_name,
        'store_id', v_store,
        'store_code', v_store_code,
        'store_name', v_store_name,
        'developer_admin', false,
        'valid', coalesce(v_valid,false),
        'status', coalesce(v_license.status,'none'),
        'billing_cycle', v_license.billing_cycle,
        'license_code', v_license.license_code,
        'plan_code', v_plan.code,
        'plan_name', v_plan.name,
        'features', coalesce(v_plan.feature_codes,'{}'::text[]),
        'max_devices', v_plan.max_devices,
        'max_stores', v_plan.max_stores,
        'used_devices', v_devices,
        'used_stores', v_stores,
        'over_limit', case
            when v_plan.id is null then false
            else v_devices > v_plan.max_devices
              or v_stores > v_plan.max_stores
        end,
        'valid_from', v_license.valid_from,
        'valid_until', v_license.valid_until,
        'days_remaining', v_days
    );
end;
$$;

revoke all on function public.ldm_license_context() from public, anon;
grant execute on function public.ldm_license_context() to authenticated;

-- ------------------------------------------------
-- 4) Helper internal: buat license key manual.
-- Hanya dipanggil oleh RPC Developer di bawah.
-- ------------------------------------------------
create or replace function public.ldm_issue_manual_license_key_internal(
    p_network_id uuid,
    p_owner_user_id uuid,
    p_plan_id uuid,
    p_billing_cycle text,
    p_source_payment_id uuid default null,
    p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
    v_plan public.license_plans%rowtype;
    v_network public.store_networks%rowtype;
    v_owner_email text;
    v_store_id uuid;
    v_store_code text;
    v_store_name text;
    v_raw text;
    v_key text;
    v_norm text;
    v_hash text;
    v_row public.license_activation_keys%rowtype;
begin
    if not public.ldm_is_license_developer() then
        raise exception 'Developer access required.';
    end if;

    select * into strict v_network
    from public.store_networks n
    where n.id = p_network_id
      and n.active = true
      and n.deleted_at is null;

    select * into strict v_plan
    from public.license_plans p
    where p.id = p_plan_id
      and p.active = true;

    if p_billing_cycle not in ('monthly','yearly','lifetime') then
        raise exception 'Billing cycle tidak valid.';
    end if;

    if v_plan.code = 'lifetime' and p_billing_cycle <> 'lifetime' then
        raise exception 'Paket Lifetime hanya dapat memakai billing lifetime.';
    end if;

    if v_plan.code <> 'lifetime' and p_billing_cycle = 'lifetime' then
        raise exception 'Billing lifetime hanya tersedia untuk paket Lifetime.';
    end if;

    if not exists(
        select 1
        from public.store_memberships sm
        join public.store_network_stores sns
          on sns.store_id = sm.store_id
         and sns.active = true
        where sns.network_id = p_network_id
          and sm.user_id = p_owner_user_id
          and sm.role = 'owner'
          and sm.active = true
    ) then
        raise exception 'Akun customer bukan Owner aktif pada network tersebut.';
    end if;

    select u.email
      into v_owner_email
    from auth.users u
    where u.id = p_owner_user_id
    limit 1;

    select s.id, s.code, s.name
      into v_store_id, v_store_code, v_store_name
    from public.store_network_stores sns
    join public.stores s on s.id = sns.store_id
    where sns.network_id = p_network_id
      and sns.active = true
      and s.deleted_at is null
    order by sns.is_primary desc, sns.joined_at asc
    limit 1;

    v_raw := upper(encode(extensions.gen_random_bytes(12),'hex'));
    v_key :=
        'LDM-' || substr(v_raw,1,4) || '-' ||
        substr(v_raw,5,4) || '-' ||
        substr(v_raw,9,4) || '-' ||
        substr(v_raw,13,4) || '-' ||
        substr(v_raw,17,4) || '-' ||
        substr(v_raw,21,4);

    v_norm := regexp_replace(upper(v_key),'[^A-Z0-9]','','g');
    v_hash := encode(
        extensions.digest(convert_to(v_norm,'UTF8'),'sha256'),
        'hex'
    );

    insert into public.license_activation_keys(
        network_id,
        owner_user_id,
        plan_id,
        billing_cycle,
        source_payment_id,
        key_hash,
        key_hint,
        status,
        issue_note,
        issued_by
    )
    values(
        p_network_id,
        p_owner_user_id,
        p_plan_id,
        p_billing_cycle,
        p_source_payment_id,
        v_hash,
        right(v_norm,6),
        'issued',
        nullif(btrim(coalesce(p_note,'')),''),
        auth.uid()
    )
    returning * into v_row;

    if p_source_payment_id is not null then
        update public.license_payments
           set provider_status = 'license_key_issued',
               raw_last_notification = coalesce(raw_last_notification,'{}'::jsonb)
                   || jsonb_build_object(
                       'license_key_id', v_row.id,
                       'license_key_hint', v_row.key_hint,
                       'license_key_issued_at', now(),
                       'license_key_issued_by', auth.uid()
                   ),
               updated_at = now()
         where id = p_source_payment_id;
    end if;

    insert into public.license_events(
        network_id,
        user_id,
        event_type,
        detail
    ) values(
        p_network_id,
        auth.uid(),
        'manual_license_key_issued',
        jsonb_build_object(
            'key_id', v_row.id,
            'key_hint', v_row.key_hint,
            'owner_user_id', p_owner_user_id,
            'plan', v_plan.code,
            'billing_cycle', p_billing_cycle,
            'payment_id', p_source_payment_id
        )
    );

    -- PENTING: raw key hanya ada di response ini. Tidak disimpan plaintext.
    return jsonb_build_object(
        'ok', true,
        'key_id', v_row.id,
        'license_key', v_key,
        'key_hint', v_row.key_hint,
        'network_id', p_network_id,
        'network_code', v_network.code,
        'network_name', v_network.name,
        'store_id', v_store_id,
        'store_code', v_store_code,
        'store_name', v_store_name,
        'owner_user_id', p_owner_user_id,
        'owner_email', v_owner_email,
        'plan_code', v_plan.code,
        'plan_name', v_plan.name,
        'billing_cycle', p_billing_cycle,
        'max_devices', v_plan.max_devices,
        'max_stores', v_plan.max_stores,
        'issued_at', v_row.issued_at,
        'source_payment_id', p_source_payment_id
    );
end;
$$;

revoke all on function public.ldm_issue_manual_license_key_internal(uuid,uuid,uuid,text,uuid,text)
from public, anon, authenticated;

-- ------------------------------------------------
-- 5) Developer membuat key dari payment yang SUDAH PAID.
-- ------------------------------------------------
create or replace function public.ldm_developer_issue_key_from_payment(
    p_payment_id uuid,
    p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_pay public.license_payments%rowtype;
begin
    if not public.ldm_is_license_developer() then
        raise exception 'Developer access required.';
    end if;

    select * into strict v_pay
    from public.license_payments pay
    where pay.id = p_payment_id
    for update;

    if v_pay.status <> 'paid' then
        raise exception 'Payment harus berstatus paid sebelum License Key dibuat.';
    end if;

    if exists(
        select 1
        from public.license_activation_keys k
        where k.source_payment_id = v_pay.id
          and k.status = 'issued'
    ) then
        raise exception 'Payment ini sudah memiliki key aktif yang belum digunakan. Revoke key lama jika perlu reissue.';
    end if;

    return public.ldm_issue_manual_license_key_internal(
        v_pay.network_id,
        v_pay.requested_by,
        v_pay.plan_id,
        v_pay.billing_cycle,
        v_pay.id,
        p_note
    );
end;
$$;

revoke all on function public.ldm_developer_issue_key_from_payment(uuid,text)
from public, anon;
grant execute on function public.ldm_developer_issue_key_from_payment(uuid,text)
to authenticated;

-- ------------------------------------------------
-- 6) Developer dapat membuat key manual tanpa record payment.
-- Cocok untuk pembayaran manual di luar flow, kompensasi, atau testing.
-- Tetap terikat Network + email Owner.
-- ------------------------------------------------
create or replace function public.ldm_developer_issue_manual_key(
    p_network_id uuid,
    p_owner_email text,
    p_plan_code text,
    p_billing_cycle text,
    p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
    v_owner uuid;
    v_plan public.license_plans%rowtype;
    v_cycle text;
begin
    if not public.ldm_is_license_developer() then
        raise exception 'Developer access required.';
    end if;

    select u.id into v_owner
    from auth.users u
    where lower(u.email) = lower(btrim(coalesce(p_owner_email,'')))
    limit 1;

    if v_owner is null then
        raise exception 'Auth user customer tidak ditemukan.';
    end if;

    select * into strict v_plan
    from public.license_plans p
    where p.code = lower(btrim(coalesce(p_plan_code,'')))
      and p.active = true;

    v_cycle := lower(btrim(coalesce(p_billing_cycle,'')));

    return public.ldm_issue_manual_license_key_internal(
        p_network_id,
        v_owner,
        v_plan.id,
        v_cycle,
        null,
        p_note
    );
end;
$$;

revoke all on function public.ldm_developer_issue_manual_key(uuid,text,text,text,text)
from public, anon;
grant execute on function public.ldm_developer_issue_manual_key(uuid,text,text,text,text)
to authenticated;

-- ------------------------------------------------
-- 7) Customer Owner mengaktifkan key manual.
-- Key terikat ke Network dan akun Owner yang ditentukan Developer.
-- ------------------------------------------------
create or replace function public.ldm_activate_manual_license_key(
    p_license_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_network uuid;
    v_norm text;
    v_hash text;
    v_key public.license_activation_keys%rowtype;
    v_plan public.license_plans%rowtype;
    v_old public.network_licenses%rowtype;
    v_base timestamptz;
    v_until timestamptz;
    v_reference text;
begin
    if auth.uid() is null then
        raise exception 'Auth session missing!';
    end if;

    if public.ldm_current_role() <> 'owner' then
        raise exception 'Hanya Owner yang dapat mengaktifkan License Key.';
    end if;

    v_network := public.ldm_current_network_id();
    if v_network is null then
        raise exception 'Network toko aktif belum tersedia.';
    end if;

    v_norm := regexp_replace(
        upper(btrim(coalesce(p_license_key,''))),
        '[^A-Z0-9]',
        '',
        'g'
    );

    if length(v_norm) < 20 then
        raise exception 'Format License Key tidak valid.';
    end if;

    v_hash := encode(
        extensions.digest(convert_to(v_norm,'UTF8'),'sha256'),
        'hex'
    );

    select * into v_key
    from public.license_activation_keys k
    where k.key_hash = v_hash
    for update;

    if v_key.id is null then
        raise exception 'License Key tidak ditemukan atau tidak valid.';
    end if;

    if v_key.status = 'activated' then
        raise exception 'License Key sudah pernah digunakan.';
    elsif v_key.status = 'revoked' then
        raise exception 'License Key telah dicabut oleh Developer.';
    elsif v_key.status = 'expired' then
        raise exception 'License Key sudah tidak berlaku.';
    elsif v_key.status <> 'issued' then
        raise exception 'Status License Key tidak dapat diaktifkan.';
    end if;

    if v_key.network_id <> v_network then
        raise exception 'License Key ini dibuat untuk Network lain.';
    end if;

    if v_key.owner_user_id <> auth.uid() then
        raise exception 'License Key ini dibuat untuk akun customer yang berbeda.';
    end if;

    select * into strict v_plan
    from public.license_plans p
    where p.id = v_key.plan_id
      and p.active = true;

    select * into v_old
    from public.network_licenses nl
    where nl.network_id = v_network
    for update;

    -- Benefit paket baru aktif sekarang. Sisa periode aktif lama tidak hilang.
    v_base := case
        when v_old.id is not null
         and v_old.valid_until is not null
         and v_old.valid_until > now()
            then v_old.valid_until
        else now()
    end;

    if v_key.billing_cycle = 'monthly' then
        v_until := v_base + interval '1 month';
    elsif v_key.billing_cycle = 'yearly' then
        v_until := v_base + interval '1 year';
    elsif v_key.billing_cycle = 'lifetime' then
        v_until := null;
    else
        raise exception 'Billing cycle License Key tidak valid.';
    end if;

    v_reference :=
        'LDM-LIC-' ||
        upper(substr(replace(v_network::text,'-',''),1,8)) || '-' ||
        v_key.key_hint;

    insert into public.network_licenses(
        network_id,
        plan_id,
        license_code,
        status,
        billing_cycle,
        valid_from,
        valid_until,
        activated_by,
        source_payment_id
    ) values(
        v_network,
        v_plan.id,
        v_reference,
        'active',
        v_key.billing_cycle,
        now(),
        v_until,
        auth.uid(),
        v_key.source_payment_id
    )
    on conflict(network_id) do update set
        plan_id = excluded.plan_id,
        license_code = excluded.license_code,
        status = 'active',
        billing_cycle = excluded.billing_cycle,
        valid_from = excluded.valid_from,
        valid_until = excluded.valid_until,
        activated_by = excluded.activated_by,
        source_payment_id = excluded.source_payment_id,
        updated_at = now();

    update public.license_activation_keys
       set status = 'activated',
           activated_at = now(),
           activated_by = auth.uid(),
           updated_at = now()
     where id = v_key.id;

    update public.license_trials
       set status = 'converted',
           converted_payment_id = coalesce(v_key.source_payment_id, converted_payment_id),
           updated_at = now()
     where network_id = v_network
       and status = 'active';

    if v_key.source_payment_id is not null then
        update public.license_payments
           set provider_status = 'license_activated',
               updated_at = now()
         where id = v_key.source_payment_id;
    end if;

    insert into public.license_events(
        network_id,
        user_id,
        event_type,
        detail
    ) values(
        v_network,
        auth.uid(),
        'manual_license_key_activated',
        jsonb_build_object(
            'key_id', v_key.id,
            'key_hint', v_key.key_hint,
            'plan', v_plan.code,
            'billing_cycle', v_key.billing_cycle,
            'valid_until', v_until,
            'payment_id', v_key.source_payment_id
        )
    );

    return public.ldm_license_context();
end;
$$;

revoke all on function public.ldm_activate_manual_license_key(text)
from public, anon;
grant execute on function public.ldm_activate_manual_license_key(text)
to authenticated;

-- ------------------------------------------------
-- 8) Developer revoke key yang belum dipakai.
-- ------------------------------------------------
create or replace function public.ldm_developer_revoke_license_key(
    p_key_id uuid,
    p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_key public.license_activation_keys%rowtype;
begin
    if not public.ldm_is_license_developer() then
        raise exception 'Developer access required.';
    end if;

    select * into strict v_key
    from public.license_activation_keys k
    where k.id = p_key_id
    for update;

    if v_key.status <> 'issued' then
        raise exception 'Hanya key berstatus issued yang dapat direvoke.';
    end if;

    update public.license_activation_keys
       set status = 'revoked',
           revoked_at = now(),
           revoked_by = auth.uid(),
           revoke_reason = nullif(btrim(coalesce(p_reason,'')),''),
           updated_at = now()
     where id = v_key.id;

    insert into public.license_events(network_id,user_id,event_type,detail)
    values(
        v_key.network_id,
        auth.uid(),
        'manual_license_key_revoked',
        jsonb_build_object(
            'key_id', v_key.id,
            'key_hint', v_key.key_hint,
            'reason', nullif(btrim(coalesce(p_reason,'')),'')
        )
    );

    return jsonb_build_object(
        'ok', true,
        'key_id', v_key.id,
        'status', 'revoked'
    );
end;
$$;

revoke all on function public.ldm_developer_revoke_license_key(uuid,text)
from public, anon;
grant execute on function public.ldm_developer_revoke_license_key(uuid,text)
to authenticated;

-- ------------------------------------------------
-- 9) Konfirmasi payment WhatsApp sekarang HANYA menandai PAID.
-- Tidak lagi mengaktifkan lisensi otomatis.
-- Developer harus membuat License Key setelah payment confirmed.
-- ------------------------------------------------
create or replace function public.ldm_developer_confirm_whatsapp_payment(
    p_payment_id uuid,
    p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_pay public.license_payments%rowtype;
begin
    if not public.ldm_is_license_developer() then
        raise exception 'Developer access required.';
    end if;

    select * into strict v_pay
    from public.license_payments pay
    where pay.id = p_payment_id
    for update;

    if v_pay.provider <> 'whatsapp_manual' then
        raise exception 'Payment ini bukan pembayaran WhatsApp manual.';
    end if;

    if v_pay.status = 'paid' then
        return jsonb_build_object(
            'ok', true,
            'already_paid', true,
            'payment_id', v_pay.id,
            'status', v_pay.status,
            'next_step', 'issue_license_key'
        );
    end if;

    if v_pay.status <> 'pending' then
        raise exception 'Hanya payment pending yang dapat dikonfirmasi.';
    end if;

    update public.license_payments
       set status = 'paid',
           provider_status = 'confirmed_waiting_license_key',
           payment_type = 'manual_whatsapp',
           paid_at = now(),
           raw_last_notification = coalesce(raw_last_notification,'{}'::jsonb)
               || jsonb_build_object(
                   'confirmed_by', auth.uid(),
                   'confirmed_at', now(),
                   'developer_note', nullif(btrim(coalesce(p_note,'')),'')
               ),
           updated_at = now()
     where id = v_pay.id;

    insert into public.license_events(network_id,user_id,event_type,detail)
    values(
        v_pay.network_id,
        auth.uid(),
        'whatsapp_payment_confirmed_waiting_key',
        jsonb_build_object(
            'payment_id', v_pay.id,
            'order_id', v_pay.provider_order_id,
            'note', nullif(btrim(coalesce(p_note,'')),'')
        )
    );

    return jsonb_build_object(
        'ok', true,
        'payment_id', v_pay.id,
        'status', 'paid',
        'next_step', 'issue_license_key'
    );
end;
$$;

revoke all on function public.ldm_developer_confirm_whatsapp_payment(uuid,text)
from public, anon;
grant execute on function public.ldm_developer_confirm_whatsapp_payment(uuid,text)
to authenticated;

-- ------------------------------------------------
-- 10) Payment request ditambah Store/Network identity untuk WA handoff.
-- ------------------------------------------------
create or replace function public.ldm_create_whatsapp_payment_request(
    p_plan_code text,
    p_billing_cycle text
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
    v_network uuid;
    v_store uuid;
    v_plan public.license_plans%rowtype;
    v_existing public.license_payments%rowtype;
    v_payment public.license_payments%rowtype;
    v_contact public.license_settings%rowtype;
    v_cycle text;
    v_amount bigint;
    v_order text;
    v_network_name text;
    v_network_code text;
    v_store_name text;
    v_store_code text;
    v_email text;
begin
    if auth.uid() is null then
        raise exception 'Auth session missing!';
    end if;

    if public.ldm_current_role() <> 'owner' then
        raise exception 'Hanya Owner yang dapat membuat request pembayaran lisensi.';
    end if;

    v_network := public.ldm_current_network_id();
    v_store := public.ldm_current_store_id();

    if v_network is null or v_store is null then
        raise exception 'Network/Store aktif belum tersedia.';
    end if;

    v_cycle := lower(btrim(coalesce(p_billing_cycle,'')));
    if v_cycle not in ('monthly','yearly','lifetime') then
        raise exception 'Billing cycle tidak valid.';
    end if;

    select * into v_plan
    from public.license_plans p
    where p.code = lower(btrim(coalesce(p_plan_code,'')))
      and p.active = true
    limit 1;

    if v_plan.id is null then
        raise exception 'Paket lisensi tidak ditemukan.';
    end if;

    if v_plan.code = 'lifetime' and v_cycle <> 'lifetime' then
        raise exception 'Paket Lifetime hanya mendukung pembayaran Lifetime.';
    end if;

    if v_plan.code <> 'lifetime' and v_cycle = 'lifetime' then
        raise exception 'Billing Lifetime hanya tersedia pada paket Lifetime.';
    end if;

    v_amount := case
        when v_cycle = 'monthly' then v_plan.monthly_price
        when v_cycle = 'yearly' then v_plan.yearly_price
        else v_plan.lifetime_price
    end;

    if coalesce(v_amount,0) <= 0 then
        raise exception 'Harga paket belum dikonfigurasi.';
    end if;

    select * into v_contact
    from public.license_settings s
    where s.id = 'default'
      and s.active = true
    limit 1;

    if v_contact.id is null then
        raise exception 'Kontak Developer belum dikonfigurasi.';
    end if;

    if v_contact.developer_whatsapp !~ '^[0-9]{8,16}$' then
        raise exception 'Nomor WhatsApp Developer belum valid. Gunakan format 628xxxxxxxxxx.';
    end if;

    select n.name, n.code
      into v_network_name, v_network_code
    from public.store_networks n
    where n.id = v_network
    limit 1;

    select s.name, s.code
      into v_store_name, v_store_code
    from public.stores s
    where s.id = v_store
    limit 1;

    select u.email
      into v_email
    from auth.users u
    where u.id = auth.uid()
    limit 1;

    select * into v_existing
    from public.license_payments pay
    where pay.network_id = v_network
      and pay.plan_id = v_plan.id
      and pay.billing_cycle = v_cycle
      and pay.provider = 'whatsapp_manual'
      and pay.status = 'pending'
    order by pay.created_at desc
    limit 1;

    if v_existing.id is not null then
        return jsonb_build_object(
            'ok', true,
            'reused', true,
            'payment_id', v_existing.id,
            'order_id', v_existing.provider_order_id,
            'plan_code', v_plan.code,
            'plan_name', v_plan.name,
            'billing_cycle', v_cycle,
            'amount', v_existing.amount,
            'currency', v_existing.currency,
            'network_id', v_network,
            'network_name', v_network_name,
            'network_code', v_network_code,
            'store_id', v_store,
            'store_name', v_store_name,
            'store_code', v_store_code,
            'owner_user_id', auth.uid(),
            'owner_email', v_email,
            'developer_whatsapp', v_contact.developer_whatsapp,
            'developer_name', v_contact.developer_display_name,
            'instruction', v_contact.payment_instruction,
            'status', v_existing.status
        );
    end if;

    v_order :=
        'LDM-WA-' ||
        to_char(clock_timestamp() at time zone 'Asia/Makassar','YYMMDDHH24MISS') || '-' ||
        upper(substr(replace(gen_random_uuid()::text,'-',''),1,8));

    insert into public.license_payments(
        network_id,
        plan_id,
        requested_by,
        provider,
        provider_order_id,
        billing_cycle,
        amount,
        currency,
        status,
        payment_type,
        provider_status,
        raw_last_notification
    ) values(
        v_network,
        v_plan.id,
        auth.uid(),
        'whatsapp_manual',
        v_order,
        v_cycle,
        v_amount,
        'IDR',
        'pending',
        'manual_transfer',
        'waiting_whatsapp',
        jsonb_build_object(
            'channel','whatsapp',
            'requested_at',now(),
            'store_id',v_store,
            'store_code',v_store_code,
            'owner_email',v_email
        )
    ) returning * into v_payment;

    insert into public.license_events(network_id,user_id,event_type,detail)
    values(
        v_network,
        auth.uid(),
        'whatsapp_payment_requested',
        jsonb_build_object(
            'payment_id',v_payment.id,
            'order_id',v_payment.provider_order_id,
            'plan',v_plan.code,
            'billing_cycle',v_cycle,
            'amount',v_amount,
            'store_id',v_store
        )
    );

    return jsonb_build_object(
        'ok', true,
        'reused', false,
        'payment_id', v_payment.id,
        'order_id', v_payment.provider_order_id,
        'plan_code', v_plan.code,
        'plan_name', v_plan.name,
        'billing_cycle', v_cycle,
        'amount', v_payment.amount,
        'currency', v_payment.currency,
        'network_id', v_network,
        'network_name', v_network_name,
        'network_code', v_network_code,
        'store_id', v_store,
        'store_name', v_store_name,
        'store_code', v_store_code,
        'owner_user_id', auth.uid(),
        'owner_email', v_email,
        'developer_whatsapp', v_contact.developer_whatsapp,
        'developer_name', v_contact.developer_display_name,
        'instruction', v_contact.payment_instruction,
        'status', v_payment.status
    );
end;
$$;

revoke all on function public.ldm_create_whatsapp_payment_request(text,text)
from public, anon;
grant execute on function public.ldm_create_whatsapp_payment_request(text,text)
to authenticated;

-- ------------------------------------------------
-- 11) Developer overview lengkap: trial, license, payment, manual keys.
-- Raw key TIDAK bisa dibaca kembali karena tidak disimpan plaintext.
-- ------------------------------------------------
create or replace function public.ldm_developer_license_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $$
declare
    v_result jsonb;
begin
    if not public.ldm_is_license_developer() then
        raise exception 'Developer access required.';
    end if;

    select jsonb_build_object(
        'summary', jsonb_build_object(
            'active_trials',(
                select count(*)
                from public.license_trials
                where status='active' and expires_at>now()
            ),
            'active_licenses',(
                select count(*)
                from public.network_licenses
                where status='active'
                  and (valid_until is null or valid_until>now())
            ),
            'paid_payments',(
                select count(*)
                from public.license_payments
                where status='paid'
            ),
            'pending_payments',(
                select count(*)
                from public.license_payments
                where status='pending'
            ),
            'issued_keys',(
                select count(*)
                from public.license_activation_keys
                where status='issued'
            )
        ),
        'trials', coalesce((
            select jsonb_agg(row_to_json(x) order by x.started_at desc)
            from (
                select
                    t.id as trial_id,
                    t.network_id,
                    n.name as network_name,
                    n.code as network_code,
                    t.started_by as user_id,
                    u.email,
                    t.started_at,
                    t.expires_at,
                    t.status,
                    p.name as plan_name
                from public.license_trials t
                join public.store_networks n on n.id=t.network_id
                join public.license_plans p on p.id=t.plan_id
                left join auth.users u on u.id=t.started_by
                order by t.started_at desc
                limit 200
            ) x
        ),'[]'::jsonb),
        'licenses', coalesce((
            select jsonb_agg(row_to_json(x) order by x.updated_at desc)
            from (
                select
                    l.id as license_id,
                    l.network_id,
                    n.name as network_name,
                    n.code as network_code,
                    p.name as plan_name,
                    p.code as plan_code,
                    l.billing_cycle,
                    case
                        when l.status in ('trialing','active')
                         and l.valid_until is not null
                         and l.valid_until <= now()
                            then 'expired'
                        else l.status
                    end as status,
                    l.license_code,
                    l.valid_from,
                    l.valid_until,
                    l.updated_at
                from public.network_licenses l
                join public.store_networks n on n.id=l.network_id
                join public.license_plans p on p.id=l.plan_id
                order by l.updated_at desc
                limit 200
            ) x
        ),'[]'::jsonb),
        'payments', coalesce((
            select jsonb_agg(row_to_json(x) order by x.created_at desc)
            from (
                select
                    pay.id as payment_id,
                    pay.provider_order_id as order_id,
                    pay.network_id,
                    n.name as network_name,
                    n.code as network_code,
                    pay.requested_by as user_id,
                    u.email,
                    p.name as plan_name,
                    p.code as plan_code,
                    pay.billing_cycle,
                    pay.amount,
                    pay.status,
                    pay.provider_status,
                    pay.created_at,
                    pay.paid_at,
                    exists(
                        select 1
                        from public.license_activation_keys k
                        where k.source_payment_id=pay.id
                          and k.status in ('issued','activated')
                    ) as has_license_key
                from public.license_payments pay
                join public.store_networks n on n.id=pay.network_id
                join public.license_plans p on p.id=pay.plan_id
                left join auth.users u on u.id=pay.requested_by
                where pay.provider='whatsapp_manual'
                order by pay.created_at desc
                limit 300
            ) x
        ),'[]'::jsonb),
        'keys', coalesce((
            select jsonb_agg(row_to_json(x) order by x.issued_at desc)
            from (
                select
                    k.id as key_id,
                    k.network_id,
                    n.name as network_name,
                    n.code as network_code,
                    k.owner_user_id,
                    u.email as owner_email,
                    p.name as plan_name,
                    p.code as plan_code,
                    k.billing_cycle,
                    k.source_payment_id,
                    k.key_hint,
                    k.status,
                    k.issued_at,
                    k.activated_at,
                    k.revoked_at,
                    k.revoke_reason
                from public.license_activation_keys k
                join public.store_networks n on n.id=k.network_id
                join public.license_plans p on p.id=k.plan_id
                left join auth.users u on u.id=k.owner_user_id
                order by k.issued_at desc
                limit 300
            ) x
        ),'[]'::jsonb)
    ) into v_result;

    return v_result;
end;
$$;

revoke all on function public.ldm_developer_license_overview()
from public, anon;
grant execute on function public.ldm_developer_license_overview()
to authenticated;

-- ------------------------------------------------
-- 12) Metadata
-- ------------------------------------------------
insert into public.ldm_system_meta(key,value)
values
    ('live_sync_stage','23.2'),
    ('schema_version','23.2'),
    ('schema_status','manual_license_key_ready'),
    ('license_activation_mode','developer_manual_key'),
    ('license_guard_mode','fail_closed'),
    ('license_feature_gating','enabled'),
    ('license_expiry_mode','lazy_auto_expire_on_check'),
    ('license_lifetime_price','2799000'),
    ('license_lifetime_devices','15'),
    ('license_lifetime_stores','8'),
    ('license_trial_plan','warung-sederhana'),
    ('license_trial_days','14')
on conflict(key) do update set
    value=excluded.value,
    updated_at=now();

commit;

-- ================================================================
-- SET NOMOR WHATSAPP DEVELOPER SETELAH SQL DI ATAS BERHASIL.
-- GANTI NILAI CONTOH INI.
-- ================================================================
-- update public.license_settings
-- set developer_whatsapp = '6281234567890',
--     developer_display_name = 'Developer LocDailyMar',
--     payment_instruction = 'Kirim bukti transfer lewat WhatsApp. Setelah pembayaran diverifikasi, Developer akan mengirim Store ID, akun customer, dan License Key.',
--     updated_at = now()
-- where id = 'default';
