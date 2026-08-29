-- =====================================================================
-- LocDailyMar TAHAP 23.1 - SERVER LISENSI 4 PAKET + TRIAL 14 HARI
-- Jalankan di project Supabase KHUSUS LISENSI milik developer.
-- JANGAN jalankan di project Cloud data toko pelanggan.
-- Aman dijalankan ulang untuk memperbarui data paket.
-- =====================================================================

begin;
create extension if not exists pgcrypto;

create table if not exists public.license_plans(
    code text primary key,
    name text not null,
    description text not null default '',
    monthly_price bigint check(monthly_price is null or monthly_price>=0),
    yearly_price bigint check(yearly_price is null or yearly_price>=0),
    one_time_price bigint check(one_time_price is null or one_time_price>=0),
    max_devices integer not null check(max_devices>0),
    max_stores integer not null check(max_stores>0),
    offline_grace_days integer not null check(offline_grace_days between 0 and 30),
    trial_days integer not null default 0 check(trial_days between 0 and 90),
    is_lifetime boolean not null default false,
    features jsonb not null default '[]'::jsonb check(jsonb_typeof(features)='array'),
    active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table if not exists public.licenses(
    id uuid primary key default gen_random_uuid(),
    key_hash text not null unique check(key_hash~'^[0-9a-f]{64}$'),
    key_prefix text not null,
    customer_name text not null,
    customer_email text,
    customer_whatsapp text,
    primary_store_code text,
    plan_code text not null references public.license_plans(code),
    billing_cycle text not null check(billing_cycle in('monthly','yearly','lifetime','trial')),
    price_paid bigint check(price_paid is null or price_paid>=0),
    status text not null default 'active' check(status in('active','suspended','revoked','expired')),
    starts_at timestamptz not null default now(),
    expires_at timestamptz,
    is_lifetime boolean not null default false,
    is_trial boolean not null default false,
    trial_identity_hash text check(trial_identity_hash is null or trial_identity_hash~'^[0-9a-f]{64}$'),
    trial_initial_installation_hash text check(trial_initial_installation_hash is null or trial_initial_installation_hash~'^[0-9a-f]{64}$'),
    trial_started_at timestamptz,
    trial_ends_at timestamptz,
    trial_converted_at timestamptz,
    max_devices_override integer check(max_devices_override is null or max_devices_override>0),
    max_stores_override integer check(max_stores_override is null or max_stores_override>0),
    order_reference text,
    note text,
    status_reason text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint licenses_expiry_valid check(
        (is_lifetime=true and expires_at is null)
        or (is_lifetime=false and expires_at>starts_at)
    )
);

create table if not exists public.license_activations(
    id uuid primary key default gen_random_uuid(),
    license_id uuid not null references public.licenses(id) on delete cascade,
    installation_hash text not null check(installation_hash~'^[0-9a-f]{64}$'),
    activation_token_hash text not null unique check(activation_token_hash~'^[0-9a-f]{64}$'),
    store_ref text not null,
    device_name text,
    platform text,
    app_version text,
    status text not null default 'active' check(status in('active','deactivated','revoked')),
    first_activated_at timestamptz not null default now(),
    last_validated_at timestamptz not null default now(),
    deactivated_at timestamptz,
    unique(license_id,installation_hash)
);

create table if not exists public.license_validation_events(
    id bigint generated always as identity primary key,
    request_id uuid not null default gen_random_uuid(),
    license_id uuid references public.licenses(id) on delete set null,
    action text not null check(action in('activate','validate','deactivate','start_trial')),
    outcome text not null check(outcome in('success','failed','blocked')),
    key_prefix text,
    installation_hash text,
    ip_hash text,
    reason text,
    detail text,
    created_at timestamptz not null default now()
);

-- Upgrade aman bila project lisensi pernah memakai skema versi lama.
alter table public.license_plans add column if not exists description text not null default '';
alter table public.license_plans add column if not exists monthly_price bigint;
alter table public.license_plans add column if not exists yearly_price bigint;
alter table public.license_plans add column if not exists one_time_price bigint;
alter table public.license_plans add column if not exists trial_days integer not null default 0;
alter table public.license_plans add column if not exists is_lifetime boolean not null default false;
alter table public.licenses add column if not exists customer_whatsapp text;
alter table public.licenses add column if not exists primary_store_code text;
alter table public.licenses add column if not exists billing_cycle text not null default 'monthly';
alter table public.licenses add column if not exists price_paid bigint;
alter table public.licenses add column if not exists order_reference text;
alter table public.licenses add column if not exists is_lifetime boolean not null default false;
alter table public.licenses add column if not exists is_trial boolean not null default false;
alter table public.licenses add column if not exists trial_identity_hash text;
alter table public.licenses add column if not exists trial_initial_installation_hash text;
alter table public.licenses add column if not exists trial_started_at timestamptz;
alter table public.licenses add column if not exists trial_ends_at timestamptz;
alter table public.licenses add column if not exists trial_converted_at timestamptz;
alter table public.license_validation_events add column if not exists request_id uuid not null default gen_random_uuid();
alter table public.license_validation_events add column if not exists detail text;

do $$ begin
    if exists(select 1 from information_schema.columns where table_schema='public' and table_name='licenses' and column_name='contact_whatsapp') then
        execute 'update public.licenses set customer_whatsapp=coalesce(customer_whatsapp,contact_whatsapp)';
    end if;
end $$;
update public.licenses set billing_cycle='trial' where is_trial=true;
update public.licenses set billing_cycle='lifetime',expires_at=null,is_lifetime=true where plan_code='LIFETIME';

create index if not exists license_activations_license_status_idx on public.license_activations(license_id,status);
create index if not exists license_activations_store_idx on public.license_activations(license_id,store_ref) where status='active';
create index if not exists license_events_created_idx on public.license_validation_events(created_at desc);
create index if not exists license_events_ip_failure_idx on public.license_validation_events(ip_hash,created_at desc) where outcome in('failed','blocked');
create unique index if not exists licenses_trial_identity_unique_idx on public.licenses(trial_identity_hash) where trial_identity_hash is not null;
create unique index if not exists licenses_trial_installation_unique_idx on public.licenses(trial_initial_installation_hash) where trial_initial_installation_hash is not null;

insert into public.license_plans(
    code,name,description,monthly_price,yearly_price,one_time_price,
    max_devices,max_stores,offline_grace_days,trial_days,is_lifetime,features,active
) values
('WARUNG_KECIL','Warung Kecil','Operasional inti satu warung',29000,299000,null,1,1,1,0,false,
 '["dashboard","attendance","pos","inventory","stock_card","stock_opname","returns","reports","shift_closing","backup_restore","app_update","promo_basic"]'::jsonb,true),
('WARUNG_SEDERHANA','Warung Sederhana','Operasional lengkap untuk satu toko',59000,599000,null,3,1,3,14,false,
 '["dashboard","attendance","pos","inventory","stock_card","stock_opname","returns","reports","shift_closing","backup_restore","app_update","promo_basic","promo_advanced","unit_conversion","expenses","suppliers","purchase_order","goods_receipt","cloud_accounts","cloud_devices","offline_queue","recovery_center"]'::jsonb,true),
('TOKO','Toko','Fitur lengkap multi-toko',99000,999000,null,10,5,7,0,false,
 '["dashboard","attendance","pos","inventory","stock_card","stock_opname","returns","reports","shift_closing","backup_restore","app_update","promo_basic","promo_advanced","unit_conversion","expenses","suppliers","purchase_order","goods_receipt","cloud_accounts","cloud_devices","offline_queue","recovery_center","multi_store","stock_transfer","cloud_control","eod","qa_security"]'::jsonb,true),
('LIFETIME','Lifetime','Seluruh fitur tanpa kedaluwarsa periode',null,null,3499000,15,8,14,0,true,
 '["dashboard","attendance","pos","inventory","stock_card","stock_opname","returns","reports","shift_closing","backup_restore","app_update","promo_basic","promo_advanced","unit_conversion","expenses","suppliers","purchase_order","goods_receipt","cloud_accounts","cloud_devices","offline_queue","recovery_center","multi_store","stock_transfer","cloud_control","eod","qa_security"]'::jsonb,true)
on conflict(code) do update set
    name=excluded.name,description=excluded.description,monthly_price=excluded.monthly_price,
    yearly_price=excluded.yearly_price,one_time_price=excluded.one_time_price,
    max_devices=excluded.max_devices,max_stores=excluded.max_stores,
    offline_grace_days=excluded.offline_grace_days,trial_days=excluded.trial_days,
    is_lifetime=excluded.is_lifetime,features=excluded.features,active=excluded.active,updated_at=now();

alter table public.license_plans enable row level security;
alter table public.licenses enable row level security;
alter table public.license_activations enable row level security;
alter table public.license_validation_events enable row level security;
revoke all on public.license_plans,public.licenses,public.license_activations,public.license_validation_events from anon,authenticated;
revoke all on sequence public.license_validation_events_id_seq from anon,authenticated;

drop view if exists public.license_trial_monitor;
create or replace view public.license_trial_monitor with(security_invoker=true) as
select l.id license_id,l.key_prefix||'…' license_key_masked,l.customer_name,l.customer_email,
       l.customer_whatsapp,l.primary_store_code,l.status,l.trial_started_at,l.trial_ends_at,
       l.trial_converted_at,
       case when l.trial_converted_at is not null then 'converted'
            when l.status='revoked' then 'revoked'
            when now()>=l.trial_ends_at then 'expired' else 'active' end trial_state,
       greatest(0,ceil(extract(epoch from(l.trial_ends_at-now()))/86400.0))::integer days_remaining,
       count(a.id) filter(where a.status='active') active_devices,
       count(distinct a.store_ref) filter(where a.status='active') active_stores,
       max(a.last_validated_at) last_seen_at
from public.licenses l left join public.license_activations a on a.license_id=l.id
where l.trial_started_at is not null
group by l.id;
revoke all on public.license_trial_monitor from public,anon,authenticated;
grant select on public.license_trial_monitor to service_role;

drop view if exists public.license_customer_monitor;
create or replace view public.license_customer_monitor with(security_invoker=true) as
select l.id,l.key_prefix||'…' license_key_masked,l.customer_name,l.customer_email,l.customer_whatsapp,
       l.primary_store_code,l.plan_code,p.name plan_name,l.billing_cycle,l.price_paid,l.status,
       l.starts_at,l.expires_at,l.is_trial,l.is_lifetime,
       coalesce(l.max_devices_override,p.max_devices) max_devices,
       coalesce(l.max_stores_override,p.max_stores) max_stores,
       count(a.id) filter(where a.status='active') active_devices,
       count(distinct a.store_ref) filter(where a.status='active') active_stores,
       max(a.last_validated_at) last_seen_at
from public.licenses l join public.license_plans p on p.code=l.plan_code
left join public.license_activations a on a.license_id=l.id
group by l.id,p.code;
revoke all on public.license_customer_monitor from public,anon,authenticated;
grant select on public.license_customer_monitor to service_role;

create or replace function public.ldm_issue_license(
    p_customer_name text,p_customer_email text,p_customer_whatsapp text,
    p_plan_code text,p_billing_cycle text,p_duration_units integer default 1,
    p_price_paid bigint default null,p_primary_store_code text default null,
    p_order_reference text default null,p_note text default null
)
returns table(license_id uuid,license_key text,plan_code text,billing_cycle text,starts_at timestamptz,expires_at timestamptz,is_lifetime boolean)
language plpgsql security definer set search_path=public,extensions as $$
declare
    v_plan public.license_plans%rowtype; v_cycle text:=lower(trim(p_billing_cycle));
    v_start timestamptz:=now(); v_expiry timestamptz; v_random text; v_key text; v_id uuid;
begin
    if coalesce(trim(p_customer_name),'')='' then raise exception 'CUSTOMER_NAME_REQUIRED'; end if;
    if coalesce(trim(p_customer_email),'')='' or position('@' in p_customer_email)<2 then raise exception 'CUSTOMER_EMAIL_INVALID'; end if;
    if coalesce(p_duration_units,0)<1 or p_duration_units>120 then raise exception 'DURATION_INVALID'; end if;
    select * into v_plan from public.license_plans where code=upper(trim(p_plan_code)) and active;
    if not found then raise exception 'PLAN_NOT_FOUND_OR_INACTIVE'; end if;
    if v_plan.is_lifetime then
        if v_cycle<>'lifetime' then raise exception 'LIFETIME_CYCLE_REQUIRED'; end if;
        v_expiry:=null;
    else
        if v_cycle='monthly' then v_expiry:=v_start+make_interval(months=>p_duration_units);
        elsif v_cycle='yearly' then v_expiry:=v_start+make_interval(years=>p_duration_units);
        else raise exception 'BILLING_CYCLE_INVALID'; end if;
    end if;
    v_random:=upper(encode(gen_random_bytes(16),'hex'));
    v_key:=format('LDM-%s-%s-%s-%s',substr(v_random,1,8),substr(v_random,9,8),substr(v_random,17,8),substr(v_random,25,8));
    insert into public.licenses(key_hash,key_prefix,customer_name,customer_email,customer_whatsapp,
        primary_store_code,plan_code,billing_cycle,price_paid,starts_at,expires_at,is_lifetime,
        order_reference,note)
    values(encode(digest(upper(v_key),'sha256'),'hex'),left(v_key,12),trim(p_customer_name),
        lower(trim(p_customer_email)),left(nullif(regexp_replace(coalesce(p_customer_whatsapp,''),'[^0-9+]','','g'),''),24),
        upper(nullif(trim(p_primary_store_code),'')),v_plan.code,v_cycle,p_price_paid,v_start,v_expiry,
        v_plan.is_lifetime,nullif(trim(p_order_reference),''),nullif(trim(p_note),'')) returning id into v_id;
    return query select v_id,v_key,v_plan.code,v_cycle,v_start,v_expiry,v_plan.is_lifetime;
end;$$;

create or replace function public.ldm_start_trial(
    p_customer_name text,p_customer_email text,p_identity_hash text,
    p_installation_hash text,p_whatsapp text,p_store_code text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_plan public.license_plans%rowtype; v_end timestamptz; v_random text; v_key text; v_id uuid;
begin
    if coalesce(trim(p_customer_name),'')='' then raise exception 'CUSTOMER_NAME_REQUIRED'; end if;
    if coalesce(trim(p_customer_email),'')='' or position('@' in p_customer_email)<2 then raise exception 'CUSTOMER_EMAIL_INVALID'; end if;
    if p_identity_hash!~'^[0-9a-f]{64}$' or p_installation_hash!~'^[0-9a-f]{64}$' then raise exception 'TRIAL_IDENTITY_INVALID'; end if;
    if length(trim(coalesce(p_store_code,'')))<3 then raise exception 'STORE_REFERENCE_INVALID'; end if;
    if exists(select 1 from public.licenses where trial_identity_hash=p_identity_hash or trial_initial_installation_hash=p_installation_hash) then raise exception 'TRIAL_ALREADY_USED'; end if;
    select * into v_plan from public.license_plans where code='WARUNG_SEDERHANA' and active;
    if not found or v_plan.trial_days<>14 then raise exception 'TRIAL_PLAN_NOT_CONFIGURED'; end if;
    v_end:=now()+make_interval(days=>v_plan.trial_days);
    v_random:=upper(encode(gen_random_bytes(16),'hex'));
    v_key:=format('LDM-%s-%s-%s-%s',substr(v_random,1,8),substr(v_random,9,8),substr(v_random,17,8),substr(v_random,25,8));
    insert into public.licenses(key_hash,key_prefix,customer_name,customer_email,customer_whatsapp,
        primary_store_code,plan_code,billing_cycle,status,starts_at,expires_at,is_lifetime,is_trial,
        trial_identity_hash,trial_initial_installation_hash,trial_started_at,trial_ends_at,
        max_devices_override,max_stores_override,note)
    values(encode(digest(v_key,'sha256'),'hex'),left(v_key,12),trim(p_customer_name),lower(trim(p_customer_email)),
        left(nullif(regexp_replace(coalesce(p_whatsapp,''),'[^0-9+]','','g'),''),24),upper(trim(p_store_code)),
        'WARUNG_SEDERHANA','trial','active',now(),v_end,false,true,p_identity_hash,p_installation_hash,
        now(),v_end,1,1,'Trial Warung Sederhana 14 hari') returning id into v_id;
    return jsonb_build_object('license_id',v_id,'license_key',v_key,'plan_code','WARUNG_SEDERHANA','trial_ends_at',v_end,'max_devices',1,'max_stores',1);
exception when unique_violation then raise exception 'TRIAL_ALREADY_USED';
end;$$;

create or replace function public.ldm_convert_trial(
    p_license_id uuid,p_target_plan_code text,p_billing_cycle text,
    p_duration_units integer default 1,p_price_paid bigint default null,
    p_order_reference text default null,p_note text default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_license public.licenses%rowtype; v_plan public.license_plans%rowtype; v_cycle text:=lower(trim(p_billing_cycle)); v_expiry timestamptz;
begin
    select * into v_license from public.licenses where id=p_license_id for update;
    if not found then raise exception 'LICENSE_NOT_FOUND'; end if;
    if not v_license.is_trial then raise exception 'LICENSE_IS_NOT_TRIAL'; end if;
    select * into v_plan from public.license_plans where code=upper(trim(p_target_plan_code)) and active;
    if not found then raise exception 'PLAN_NOT_FOUND_OR_INACTIVE'; end if;
    if v_plan.is_lifetime then if v_cycle<>'lifetime' then raise exception 'LIFETIME_CYCLE_REQUIRED'; end if; v_expiry:=null;
    elsif v_cycle='monthly' then v_expiry:=now()+make_interval(months=>greatest(1,p_duration_units));
    elsif v_cycle='yearly' then v_expiry:=now()+make_interval(years=>greatest(1,p_duration_units));
    else raise exception 'BILLING_CYCLE_INVALID'; end if;
    update public.licenses set plan_code=v_plan.code,billing_cycle=v_cycle,price_paid=p_price_paid,
        starts_at=now(),expires_at=v_expiry,is_lifetime=v_plan.is_lifetime,is_trial=false,
        trial_converted_at=now(),max_devices_override=null,max_stores_override=null,status='active',
        status_reason='Trial dikonversi menjadi lisensi berbayar',order_reference=nullif(trim(p_order_reference),''),
        note=coalesce(nullif(trim(p_note),''),note),updated_at=now() where id=p_license_id;
    update public.license_activations set status='active',deactivated_at=null,last_validated_at=now()
      where license_id=p_license_id and status='revoked';
    return jsonb_build_object('ok',true,'license_id',p_license_id,'plan_code',v_plan.code,'billing_cycle',v_cycle,'expires_at',v_expiry,'is_lifetime',v_plan.is_lifetime);
end;$$;

create or replace function public.ldm_renew_license(
    p_license_id uuid,p_billing_cycle text,p_duration_units integer default 1,
    p_price_paid bigint default null,p_order_reference text default null,p_note text default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_license public.licenses%rowtype; v_cycle text:=lower(trim(p_billing_cycle)); v_base timestamptz; v_expiry timestamptz;
begin
    select * into v_license from public.licenses where id=p_license_id for update;
    if not found then raise exception 'LICENSE_NOT_FOUND'; end if;
    if v_license.is_lifetime then raise exception 'LIFETIME_LICENSE_DOES_NOT_REQUIRE_RENEWAL'; end if;
    if greatest(1,p_duration_units)>120 then raise exception 'DURATION_INVALID'; end if;
    v_base:=greatest(now(),v_license.expires_at);
    if v_cycle='monthly' then v_expiry:=v_base+make_interval(months=>greatest(1,p_duration_units));
    elsif v_cycle='yearly' then v_expiry:=v_base+make_interval(years=>greatest(1,p_duration_units));
    else raise exception 'BILLING_CYCLE_INVALID'; end if;
    update public.licenses set billing_cycle=v_cycle,expires_at=v_expiry,price_paid=coalesce(p_price_paid,price_paid),
        status='active',status_reason='Lisensi diperpanjang',order_reference=coalesce(nullif(trim(p_order_reference),''),order_reference),
        note=coalesce(nullif(trim(p_note),''),note),updated_at=now() where id=p_license_id;
    update public.license_activations set status='active',deactivated_at=null,last_validated_at=now()
      where license_id=p_license_id and status='revoked';
    return jsonb_build_object('ok',true,'license_id',p_license_id,'status','active','expires_at',v_expiry);
end;$$;

create or replace function public.ldm_set_license_status(p_license_id uuid,p_status text,p_reason text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_status text:=lower(trim(p_status)); v_lifetime boolean;
begin
    if v_status not in('active','suspended','revoked','expired') then raise exception 'INVALID_LICENSE_STATUS'; end if;
    select is_lifetime into v_lifetime from public.licenses where id=p_license_id;
    if not found then raise exception 'LICENSE_NOT_FOUND'; end if;
    if v_lifetime and v_status='expired' then raise exception 'LIFETIME_LICENSE_CANNOT_EXPIRE'; end if;
    update public.licenses set status=v_status,status_reason=nullif(trim(p_reason),''),updated_at=now() where id=p_license_id;
    if v_status in('revoked','expired') then update public.license_activations set status='revoked',deactivated_at=now() where license_id=p_license_id and status='active'; end if;
    return jsonb_build_object('ok',true,'license_id',p_license_id,'status',v_status);
end;$$;

create or replace function public.ldm_license_activate(
    p_key_hash text,p_installation_hash text,p_activation_token_hash text,p_store_ref text,
    p_device_name text,p_platform text,p_app_version text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_license public.licenses%rowtype; v_plan public.license_plans%rowtype; v_activation public.license_activations%rowtype;
        v_max_devices integer; v_max_stores integer; v_device_count integer; v_store_count integer; v_store text:=upper(trim(p_store_ref));
begin
    if p_installation_hash!~'^[0-9a-f]{64}$' or p_activation_token_hash!~'^[0-9a-f]{64}$' then raise exception 'ACTIVATION_ID_INVALID'; end if;
    if length(v_store)<3 or length(v_store)>100 then raise exception 'STORE_REFERENCE_INVALID'; end if;
    select * into v_license from public.licenses where key_hash=lower(trim(p_key_hash)) for update;
    if not found then raise exception 'LICENSE_KEY_INVALID'; end if;
    perform pg_advisory_xact_lock(hashtextextended(v_license.id::text,231));
    select * into v_plan from public.license_plans where code=v_license.plan_code and active;
    if not found then raise exception 'PLAN_INACTIVE'; end if;
    if not v_license.is_lifetime and now()>=v_license.expires_at then
        update public.licenses set status='expired',status_reason='Masa berlaku berakhir otomatis',updated_at=now() where id=v_license.id;
        update public.license_activations set status='revoked',deactivated_at=now() where license_id=v_license.id and status='active';
        raise exception 'LICENSE_EXPIRED';
    end if;
    if v_license.status='suspended' then raise exception 'LICENSE_SUSPENDED';
    elsif v_license.status='revoked' then raise exception 'LICENSE_REVOKED';
    elsif v_license.status='expired' then raise exception 'LICENSE_EXPIRED';
    elsif v_license.status<>'active' then raise exception 'LICENSE_NOT_ACTIVE'; end if;
    v_max_devices:=coalesce(v_license.max_devices_override,v_plan.max_devices);
    v_max_stores:=coalesce(v_license.max_stores_override,v_plan.max_stores);
    select * into v_activation from public.license_activations where license_id=v_license.id and installation_hash=lower(trim(p_installation_hash)) for update;
    if found then
        -- Hitung kuota tanpa baris perangkat ini. Ini mencegah perangkat lama
        -- diaktifkan kembali setelah kuotanya sudah dipakai perangkat lain.
        select count(*) into v_device_count from public.license_activations
        where license_id=v_license.id and status='active' and id<>v_activation.id;
        if v_device_count>=v_max_devices then raise exception 'DEVICE_LIMIT_REACHED'; end if;
        select count(distinct store_ref) into v_store_count from public.license_activations
        where license_id=v_license.id and status='active' and id<>v_activation.id;
        if not exists(select 1 from public.license_activations where license_id=v_license.id and status='active' and id<>v_activation.id and store_ref=v_store)
           and v_store_count>=v_max_stores then raise exception 'STORE_LIMIT_REACHED'; end if;
        update public.license_activations set activation_token_hash=lower(trim(p_activation_token_hash)),store_ref=v_store,
            device_name=left(nullif(trim(p_device_name),''),120),platform=left(nullif(trim(p_platform),''),120),
            app_version=left(nullif(trim(p_app_version),''),40),status='active',last_validated_at=now(),deactivated_at=null where id=v_activation.id;
    else
        select count(*) into v_device_count from public.license_activations where license_id=v_license.id and status='active';
        if v_device_count>=v_max_devices then raise exception 'DEVICE_LIMIT_REACHED'; end if;
        select count(distinct store_ref) into v_store_count from public.license_activations where license_id=v_license.id and status='active';
        if not exists(select 1 from public.license_activations where license_id=v_license.id and status='active' and store_ref=v_store) and v_store_count>=v_max_stores then raise exception 'STORE_LIMIT_REACHED'; end if;
        insert into public.license_activations(license_id,installation_hash,activation_token_hash,store_ref,device_name,platform,app_version)
        values(v_license.id,lower(trim(p_installation_hash)),lower(trim(p_activation_token_hash)),v_store,left(nullif(trim(p_device_name),''),120),left(nullif(trim(p_platform),''),120),left(nullif(trim(p_app_version),''),40));
    end if;
    return jsonb_build_object('license_id',v_license.id,'customer_name',v_license.customer_name,'plan_code',v_plan.code,'plan_name',v_plan.name,
      'features',v_plan.features,'max_devices',v_max_devices,'max_stores',v_max_stores,'offline_grace_days',v_plan.offline_grace_days,
      'is_lifetime',v_license.is_lifetime,'is_trial',v_license.is_trial,'trial_ends_at',v_license.trial_ends_at,'license_expires_at',v_license.expires_at,'store_ref',v_store);
end;$$;

create or replace function public.ldm_license_validate(p_activation_token_hash text,p_installation_hash text,p_store_ref text,p_app_version text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_activation public.license_activations%rowtype; v_license public.licenses%rowtype; v_plan public.license_plans%rowtype;
begin
    select * into v_activation from public.license_activations where activation_token_hash=lower(trim(p_activation_token_hash)) and installation_hash=lower(trim(p_installation_hash)) and status='active' for update;
    if not found then raise exception 'ACTIVATION_NOT_FOUND'; end if;
    if upper(trim(coalesce(p_store_ref,'')))<>v_activation.store_ref then raise exception 'STORE_REFERENCE_MISMATCH'; end if;
    select * into v_license from public.licenses where id=v_activation.license_id for update;
    select * into v_plan from public.license_plans where code=v_license.plan_code and active;
    if not found then raise exception 'PLAN_INACTIVE'; end if;
    if not v_license.is_lifetime and now()>=v_license.expires_at then
        update public.licenses set status='expired',status_reason='Masa berlaku berakhir otomatis',updated_at=now() where id=v_license.id;
        update public.license_activations set status='revoked',deactivated_at=now() where license_id=v_license.id and status='active';
        raise exception 'LICENSE_EXPIRED';
    end if;
    if v_license.status='suspended' then raise exception 'LICENSE_SUSPENDED';
    elsif v_license.status='revoked' then raise exception 'LICENSE_REVOKED';
    elsif v_license.status='expired' then raise exception 'LICENSE_EXPIRED';
    elsif v_license.status<>'active' then raise exception 'LICENSE_NOT_ACTIVE'; end if;
    update public.license_activations set last_validated_at=now(),app_version=left(nullif(trim(p_app_version),''),40) where id=v_activation.id;
    return jsonb_build_object('license_id',v_license.id,'customer_name',v_license.customer_name,'plan_code',v_plan.code,'plan_name',v_plan.name,
      'features',v_plan.features,'max_devices',coalesce(v_license.max_devices_override,v_plan.max_devices),
      'max_stores',coalesce(v_license.max_stores_override,v_plan.max_stores),'offline_grace_days',v_plan.offline_grace_days,
      'is_lifetime',v_license.is_lifetime,'is_trial',v_license.is_trial,'trial_ends_at',v_license.trial_ends_at,
      'license_expires_at',v_license.expires_at,'store_ref',v_activation.store_ref);
end;$$;

create or replace function public.ldm_license_deactivate(p_activation_token_hash text,p_installation_hash text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
    update public.license_activations set status='deactivated',deactivated_at=now(),last_validated_at=now()
    where activation_token_hash=lower(trim(p_activation_token_hash)) and installation_hash=lower(trim(p_installation_hash)) and status='active' returning id into v_id;
    if v_id is null then raise exception 'ACTIVATION_NOT_FOUND'; end if;
    return jsonb_build_object('ok',true,'activation_id',v_id,'status','deactivated');
end;$$;

revoke all on function public.ldm_issue_license(text,text,text,text,text,integer,bigint,text,text,text) from public,anon,authenticated;
revoke all on function public.ldm_start_trial(text,text,text,text,text,text) from public,anon,authenticated;
revoke all on function public.ldm_convert_trial(uuid,text,text,integer,bigint,text,text) from public,anon,authenticated;
revoke all on function public.ldm_renew_license(uuid,text,integer,bigint,text,text) from public,anon,authenticated;
revoke all on function public.ldm_set_license_status(uuid,text,text) from public,anon,authenticated;
revoke all on function public.ldm_license_activate(text,text,text,text,text,text,text) from public,anon,authenticated;
revoke all on function public.ldm_license_validate(text,text,text,text) from public,anon,authenticated;
revoke all on function public.ldm_license_deactivate(text,text) from public,anon,authenticated;
grant execute on function public.ldm_issue_license(text,text,text,text,text,integer,bigint,text,text,text) to service_role;
grant execute on function public.ldm_start_trial(text,text,text,text,text,text) to service_role;
grant execute on function public.ldm_convert_trial(uuid,text,text,integer,bigint,text,text) to service_role;
grant execute on function public.ldm_renew_license(uuid,text,integer,bigint,text,text) to service_role;
grant execute on function public.ldm_set_license_status(uuid,text,text) to service_role;
grant execute on function public.ldm_license_activate(text,text,text,text,text,text,text) to service_role;
grant execute on function public.ldm_license_validate(text,text,text,text) to service_role;
grant execute on function public.ldm_license_deactivate(text,text) to service_role;

commit;

-- CEK HASIL (jalankan sesudah migration sukses):
select code,name,monthly_price,yearly_price,one_time_price,max_devices,max_stores,trial_days,is_lifetime,active
from public.license_plans order by case code when 'WARUNG_KECIL' then 1 when 'WARUNG_SEDERHANA' then 2 when 'TOKO' then 3 else 4 end;
