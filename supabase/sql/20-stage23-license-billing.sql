-- ================================================================
-- LocDailyMar - TAHAP 23
-- Lisensi Berbayar + Trial 14 Hari + Kuota Toko/Device + Billing
-- Baseline: TAHAP 22.2
-- ================================================================

begin;

-- ------------------------------------------------
-- Paket lisensi
-- Harga adalah rekomendasi awal dan dapat diubah developer lewat SQL.
-- ------------------------------------------------
create table if not exists public.license_plans (
    id uuid primary key default gen_random_uuid(),
    code text not null unique,
    name text not null,
    description text,
    monthly_price bigint,
    yearly_price bigint,
    lifetime_price bigint,
    max_devices integer not null check (max_devices > 0),
    max_stores integer not null check (max_stores > 0),
    trial_days integer not null default 0 check (trial_days >= 0),
    trial_enabled boolean not null default false,
    active boolean not null default true,
    sort_order integer not null default 100,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint license_plan_price_check check (
        coalesce(monthly_price,0) >= 0 and
        coalesce(yearly_price,0) >= 0 and
        coalesce(lifetime_price,0) >= 0
    )
);

insert into public.license_plans(
    code,name,description,monthly_price,yearly_price,lifetime_price,
    max_devices,max_stores,trial_days,trial_enabled,sort_order
) values
    ('warung-kecil','Warung Kecil','Paket paling ringan untuk satu warung dan perangkat terbatas.',29000,299000,null,2,1,0,false,10),
    ('warung-sederhana','Warung Sederhana','Paket rekomendasi untuk usaha kecil yang mulai memakai beberapa perangkat/toko.',59000,599000,null,4,2,14,true,20),
    ('toko','Toko','Untuk toko yang membutuhkan lebih banyak perangkat, akun, dan cabang.',99000,999000,null,8,4,0,false,30),
    ('lifetime','Lifetime','Bayar sekali. Kuota tertinggi paket standar LocDailyMar.',null,null,2499000,15,8,0,false,40)
on conflict (code) do update set
    name=excluded.name,
    description=excluded.description,
    monthly_price=excluded.monthly_price,
    yearly_price=excluded.yearly_price,
    lifetime_price=excluded.lifetime_price,
    max_devices=excluded.max_devices,
    max_stores=excluded.max_stores,
    trial_days=excluded.trial_days,
    trial_enabled=excluded.trial_enabled,
    active=true,
    sort_order=excluded.sort_order,
    updated_at=now();

alter table public.license_plans enable row level security;
revoke insert,update,delete on public.license_plans from anon,authenticated;
grant select on public.license_plans to authenticated;
drop policy if exists license_plans_authenticated_read on public.license_plans;
create policy license_plans_authenticated_read on public.license_plans
for select to authenticated using (active=true);

-- ------------------------------------------------
-- Developer admin. Isi lewat template SQL terpisah.
-- ------------------------------------------------
create table if not exists public.license_developer_admins (
    user_id uuid primary key references auth.users(id) on delete cascade,
    created_at timestamptz not null default now()
);
alter table public.license_developer_admins enable row level security;
revoke all on public.license_developer_admins from anon,authenticated;

create or replace function public.ldm_is_license_developer()
returns boolean
language sql
stable
security definer
set search_path=public,pg_temp
as $$
    select exists(
        select 1 from public.license_developer_admins d
        where d.user_id=auth.uid()
    );
$$;
revoke all on function public.ldm_is_license_developer() from public,anon;
grant execute on function public.ldm_is_license_developer() to authenticated;

-- ------------------------------------------------
-- Helper network aktif
-- ------------------------------------------------
create or replace function public.ldm_current_network_id()
returns uuid
language sql
stable
security definer
set search_path=public,pg_temp
as $$
    select sns.network_id
    from public.store_network_stores sns
    where sns.store_id=public.ldm_current_store_id()
      and sns.active=true
    limit 1;
$$;
revoke all on function public.ldm_current_network_id() from public,anon;
grant execute on function public.ldm_current_network_id() to authenticated;

-- ------------------------------------------------
-- Lisensi per jaringan toko
-- ------------------------------------------------
create table if not exists public.network_licenses (
    id uuid primary key default gen_random_uuid(),
    network_id uuid not null unique references public.store_networks(id) on delete cascade,
    plan_id uuid not null references public.license_plans(id) on delete restrict,
    license_code text not null unique,
    status text not null check (status in ('trialing','active','expired','suspended')),
    billing_cycle text not null check (billing_cycle in ('trial','monthly','yearly','lifetime')),
    valid_from timestamptz not null,
    valid_until timestamptz,
    activated_by uuid references auth.users(id) on delete set null,
    source_payment_id uuid,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    version bigint not null default 1
);
create index if not exists network_licenses_status_idx on public.network_licenses(status,valid_until);

drop trigger if exists trg_network_licenses_touch on public.network_licenses;
create trigger trg_network_licenses_touch before update on public.network_licenses
for each row execute function public.ldm_touch_row();

alter table public.network_licenses enable row level security;
revoke insert,update,delete on public.network_licenses from anon,authenticated;
grant select on public.network_licenses to authenticated;
drop policy if exists network_license_member_read on public.network_licenses;
create policy network_license_member_read on public.network_licenses
for select to authenticated using (
    exists(
        select 1
        from public.store_network_stores sns
        join public.store_memberships sm on sm.store_id=sns.store_id
        where sns.network_id=network_licenses.network_id
          and sns.active=true
          and sm.user_id=auth.uid()
          and sm.active=true
    )
    or public.ldm_is_license_developer()
);

-- ------------------------------------------------
-- Trial: satu kali per network DAN satu kali per Auth user.
-- ------------------------------------------------
create table if not exists public.license_trials (
    id uuid primary key default gen_random_uuid(),
    network_id uuid not null unique references public.store_networks(id) on delete cascade,
    plan_id uuid not null references public.license_plans(id) on delete restrict,
    started_by uuid not null unique references auth.users(id) on delete restrict,
    started_at timestamptz not null default now(),
    expires_at timestamptz not null,
    status text not null default 'active' check (status in ('active','converted','expired','cancelled')),
    converted_payment_id uuid,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);
alter table public.license_trials enable row level security;
revoke all on public.license_trials from anon,authenticated;

-- ------------------------------------------------
-- Payment records. Browser hanya read milik network sendiri.
-- Write berasal dari Edge Function / service role.
-- ------------------------------------------------
create table if not exists public.license_payments (
    id uuid primary key default gen_random_uuid(),
    network_id uuid not null references public.store_networks(id) on delete restrict,
    plan_id uuid not null references public.license_plans(id) on delete restrict,
    requested_by uuid not null references auth.users(id) on delete restrict,
    provider text not null default 'midtrans',
    provider_order_id text not null unique,
    provider_transaction_id text,
    billing_cycle text not null check (billing_cycle in ('monthly','yearly','lifetime')),
    amount bigint not null check (amount > 0),
    currency text not null default 'IDR',
    status text not null default 'pending' check (status in ('pending','paid','failed','expired','cancelled','refunded')),
    payment_type text,
    provider_status text,
    snap_token text,
    redirect_url text,
    paid_at timestamptz,
    raw_last_notification jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    version bigint not null default 1
);
create index if not exists license_payments_network_idx on public.license_payments(network_id,created_at desc);
create index if not exists license_payments_status_idx on public.license_payments(status,created_at desc);

drop trigger if exists trg_license_payments_touch on public.license_payments;
create trigger trg_license_payments_touch before update on public.license_payments
for each row execute function public.ldm_touch_row();

alter table public.license_payments enable row level security;
revoke insert,update,delete on public.license_payments from anon,authenticated;
grant select on public.license_payments to authenticated;
drop policy if exists license_payment_owner_read on public.license_payments;
create policy license_payment_owner_read on public.license_payments
for select to authenticated using (
    network_id=public.ldm_current_network_id()
    and public.ldm_current_role()='owner'
    or public.ldm_is_license_developer()
);

-- FK source payment ditambahkan setelah payments tersedia.
do $$ begin
    if not exists (
        select 1 from pg_constraint where conname='network_licenses_source_payment_fk'
    ) then
        alter table public.network_licenses
        add constraint network_licenses_source_payment_fk
        foreign key(source_payment_id) references public.license_payments(id) on delete set null;
    end if;
end $$;

-- ------------------------------------------------
-- Event audit untuk developer.
-- ------------------------------------------------
create table if not exists public.license_events (
    id uuid primary key default gen_random_uuid(),
    network_id uuid references public.store_networks(id) on delete cascade,
    user_id uuid references auth.users(id) on delete set null,
    event_type text not null,
    detail jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now()
);
create index if not exists license_events_network_idx on public.license_events(network_id,created_at desc);
alter table public.license_events enable row level security;
revoke all on public.license_events from anon,authenticated;

-- ------------------------------------------------
-- Plan list RPC
-- ------------------------------------------------
create or replace function public.ldm_license_plans()
returns table(
    id uuid,code text,name text,description text,
    monthly_price bigint,yearly_price bigint,lifetime_price bigint,
    max_devices integer,max_stores integer,trial_days integer,trial_enabled boolean
)
language sql
stable
security definer
set search_path=public,pg_temp
as $$
    select p.id,p.code,p.name,p.description,p.monthly_price,p.yearly_price,p.lifetime_price,
           p.max_devices,p.max_stores,p.trial_days,p.trial_enabled
    from public.license_plans p
    where p.active=true
    order by p.sort_order,p.name;
$$;
revoke all on function public.ldm_license_plans() from public,anon;
grant execute on function public.ldm_license_plans() to authenticated;

-- ------------------------------------------------
-- Context lisensi. Existing over-limit tidak langsung diputus;
-- penambahan store/device baru tetap diblokir trigger.
-- ------------------------------------------------
create or replace function public.ldm_license_context()
returns jsonb
language plpgsql
stable
security definer
set search_path=public,pg_temp
as $$
declare
    v_network uuid;
    v_license public.network_licenses%rowtype;
    v_plan public.license_plans%rowtype;
    v_stores integer:=0;
    v_devices integer:=0;
    v_valid boolean:=false;
    v_dev boolean:=false;
    v_days integer:=null;
begin
    if auth.uid() is null then
        raise exception 'Auth session missing!';
    end if;

    v_network:=public.ldm_current_network_id();
    if v_network is null then raise exception 'Network toko aktif belum tersedia.'; end if;
    v_dev:=public.ldm_is_license_developer();

    select count(*)::int into v_stores
    from public.store_network_stores sns
    where sns.network_id=v_network and sns.active=true;

    select count(distinct d.client_device_id)::int into v_devices
    from public.devices d
    join public.store_network_stores sns on sns.store_id=d.store_id and sns.active=true
    where sns.network_id=v_network and d.status='active' and d.deleted_at is null;

    if v_dev then
        return jsonb_build_object(
            'network_id',v_network,'developer_admin',true,'valid',true,
            'status','developer','billing_cycle','developer','license_code','DEVELOPER',
            'plan_code','developer','plan_name','Developer Override',
            'max_devices',999,'max_stores',999,'used_devices',v_devices,'used_stores',v_stores,
            'over_limit',false,'valid_from',null,'valid_until',null,'days_remaining',null
        );
    end if;

    select * into v_license from public.network_licenses nl where nl.network_id=v_network limit 1;
    if v_license.id is not null then
        select * into v_plan from public.license_plans p where p.id=v_license.plan_id limit 1;
        v_valid := v_license.status in ('trialing','active')
                   and (v_license.valid_until is null or v_license.valid_until > now());
        if v_license.valid_until is not null then
            v_days:=greatest(0,ceil(extract(epoch from (v_license.valid_until-now()))/86400.0)::int);
        end if;
    end if;

    return jsonb_build_object(
        'network_id',v_network,
        'developer_admin',false,
        'valid',coalesce(v_valid,false),
        'status',coalesce(v_license.status,'none'),
        'billing_cycle',v_license.billing_cycle,
        'license_code',v_license.license_code,
        'plan_code',v_plan.code,
        'plan_name',v_plan.name,
        'max_devices',v_plan.max_devices,
        'max_stores',v_plan.max_stores,
        'used_devices',v_devices,
        'used_stores',v_stores,
        'over_limit',case when v_plan.id is null then false else v_devices>v_plan.max_devices or v_stores>v_plan.max_stores end,
        'valid_from',v_license.valid_from,
        'valid_until',v_license.valid_until,
        'days_remaining',v_days
    );
end;
$$;
revoke all on function public.ldm_license_context() from public,anon;
grant execute on function public.ldm_license_context() to authenticated;

-- ------------------------------------------------
-- Start trial Warung Sederhana 14 hari, Owner-only.
-- Developer dapat melihat claim dari Developer License Center.
-- ------------------------------------------------
create or replace function public.ldm_start_sederhana_trial()
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
    v_network uuid;
    v_plan public.license_plans%rowtype;
    v_trial public.license_trials%rowtype;
    v_code text;
begin
    if public.ldm_current_role()<>'owner' then raise exception 'Hanya Owner yang dapat memulai trial.'; end if;
    v_network:=public.ldm_current_network_id();
    if v_network is null then raise exception 'Network toko aktif belum tersedia.'; end if;

    if exists(select 1 from public.network_licenses nl where nl.network_id=v_network and nl.billing_cycle <> 'trial') then
        raise exception 'Network ini sudah pernah memiliki lisensi berbayar dan tidak dapat memulai trial.';
    end if;

    if exists(select 1 from public.license_trials t where t.network_id=v_network) then
        raise exception 'Network ini sudah pernah menggunakan masa trial.';
    end if;
    if exists(select 1 from public.license_trials t where t.started_by=auth.uid()) then
        raise exception 'Akun Owner ini sudah pernah menggunakan masa trial.';
    end if;

    select * into strict v_plan from public.license_plans p
    where p.code='warung-sederhana' and p.active=true and p.trial_enabled=true;

    v_code:='LDM-'||upper(substr(replace(v_network::text,'-',''),1,8))||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,8));

    insert into public.license_trials(network_id,plan_id,started_by,expires_at)
    values(v_network,v_plan.id,auth.uid(),now()+make_interval(days=>v_plan.trial_days))
    returning * into v_trial;

    insert into public.network_licenses(
        network_id,plan_id,license_code,status,billing_cycle,valid_from,valid_until,activated_by
    ) values(
        v_network,v_plan.id,v_code,'trialing','trial',v_trial.started_at,v_trial.expires_at,auth.uid()
    )
    on conflict(network_id) do update set
        plan_id=excluded.plan_id,license_code=excluded.license_code,status='trialing',billing_cycle='trial',
        valid_from=excluded.valid_from,valid_until=excluded.valid_until,activated_by=excluded.activated_by,
        source_payment_id=null,updated_at=now();

    insert into public.license_events(network_id,user_id,event_type,detail)
    values(v_network,auth.uid(),'trial_started',jsonb_build_object(
        'plan','warung-sederhana','days',v_plan.trial_days,'expires_at',v_trial.expires_at
    ));

    return public.ldm_license_context();
end;
$$;
revoke all on function public.ldm_start_sederhana_trial() from public,anon;
grant execute on function public.ldm_start_sederhana_trial() to authenticated;

-- ------------------------------------------------
-- Payment history Owner
-- ------------------------------------------------
create or replace function public.ldm_license_payment_history()
returns table(
    id uuid,provider_order_id text,plan_name text,billing_cycle text,
    amount bigint,status text,payment_type text,provider_status text,created_at timestamptz,paid_at timestamptz
)
language sql
stable
security definer
set search_path=public,pg_temp
as $$
    select pay.id,pay.provider_order_id,p.name,pay.billing_cycle,pay.amount,pay.status,
           pay.payment_type,pay.provider_status,pay.created_at,pay.paid_at
    from public.license_payments pay
    join public.license_plans p on p.id=pay.plan_id
    where pay.network_id=public.ldm_current_network_id()
      and public.ldm_current_role()='owner'
    order by pay.created_at desc
    limit 100;
$$;
revoke all on function public.ldm_license_payment_history() from public,anon;
grant execute on function public.ldm_license_payment_history() to authenticated;

-- ------------------------------------------------
-- Aktivasi dari webhook/service_role saja.
-- Renewal menambah masa aktif dari expiry sekarang jika masih aktif.
-- ------------------------------------------------
create or replace function public.ldm_activate_license_from_payment(p_payment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
    v_pay public.license_payments%rowtype;
    v_plan public.license_plans%rowtype;
    v_old public.network_licenses%rowtype;
    v_from timestamptz;
    v_until timestamptz;
    v_code text;
begin
    select * into strict v_pay from public.license_payments where id=p_payment_id for update;
    if v_pay.status<>'paid' then raise exception 'Payment belum berstatus paid.'; end if;
    select * into strict v_plan from public.license_plans where id=v_pay.plan_id;
    select * into v_old from public.network_licenses where network_id=v_pay.network_id for update;

    if v_pay.billing_cycle='lifetime' then
        v_from:=now(); v_until:=null;
    else
        v_from:=case when v_old.id is not null and v_old.status='active' and v_old.valid_until>now() then v_old.valid_until else now() end;
        if v_pay.billing_cycle='monthly' then v_until:=v_from+interval '1 month';
        elsif v_pay.billing_cycle='yearly' then v_until:=v_from+interval '1 year';
        else raise exception 'Billing cycle payment tidak valid.';
        end if;
    end if;

    v_code:=coalesce(v_old.license_code,
        'LDM-'||upper(substr(replace(v_pay.network_id::text,'-',''),1,8))||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,8)));

    insert into public.network_licenses(
        network_id,plan_id,license_code,status,billing_cycle,valid_from,valid_until,activated_by,source_payment_id
    ) values(
        v_pay.network_id,v_plan.id,v_code,'active',v_pay.billing_cycle,
        case when v_pay.billing_cycle='lifetime' then now() else v_from end,
        v_until,v_pay.requested_by,v_pay.id
    )
    on conflict(network_id) do update set
        plan_id=excluded.plan_id,status='active',billing_cycle=excluded.billing_cycle,
        valid_from=excluded.valid_from,valid_until=excluded.valid_until,activated_by=excluded.activated_by,
        source_payment_id=excluded.source_payment_id,updated_at=now();

    update public.license_trials
       set status='converted',converted_payment_id=v_pay.id,updated_at=now()
     where network_id=v_pay.network_id and status='active';

    insert into public.license_events(network_id,user_id,event_type,detail)
    values(v_pay.network_id,v_pay.requested_by,'license_activated',jsonb_build_object(
        'plan',v_plan.code,'billing_cycle',v_pay.billing_cycle,'payment_id',v_pay.id,'valid_until',v_until
    ));

    return jsonb_build_object('ok',true,'network_id',v_pay.network_id,'plan',v_plan.code,'billing_cycle',v_pay.billing_cycle,'valid_until',v_until);
end;
$$;
revoke all on function public.ldm_activate_license_from_payment(uuid) from public,anon,authenticated;
grant execute on function public.ldm_activate_license_from_payment(uuid) to service_role;

-- ------------------------------------------------
-- Developer overview: developer dapat tahu siapa mulai trial.
-- ------------------------------------------------
create or replace function public.ldm_developer_license_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path=public,auth,pg_temp
as $$
declare v_result jsonb;
begin
    if not public.ldm_is_license_developer() then raise exception 'Developer access required.'; end if;
    select jsonb_build_object(
        'summary',jsonb_build_object(
            'active_trials',(select count(*) from public.license_trials where status='active' and expires_at>now()),
            'active_licenses',(select count(*) from public.network_licenses where status='active' and (valid_until is null or valid_until>now())),
            'paid_payments',(select count(*) from public.license_payments where status='paid'),
            'pending_payments',(select count(*) from public.license_payments where status='pending')
        ),
        'trials',coalesce((
            select jsonb_agg(x order by (x->>'started_at') desc) from (
                select jsonb_build_object(
                    'trial_id',t.id,'network_id',t.network_id,'network_name',n.name,'network_code',n.code,
                    'user_id',t.started_by,'email',u.email,'started_at',t.started_at,'expires_at',t.expires_at,
                    'status',t.status,'plan_name',p.name
                ) x
                from public.license_trials t
                join public.store_networks n on n.id=t.network_id
                join public.license_plans p on p.id=t.plan_id
                left join auth.users u on u.id=t.started_by
                order by t.started_at desc limit 200
            ) q
        ),'[]'::jsonb),
        'licenses',coalesce((
            select jsonb_agg(x order by (x->>'updated_at') desc) from (
                select jsonb_build_object(
                    'license_id',l.id,'network_id',l.network_id,'network_name',n.name,'network_code',n.code,
                    'plan_name',p.name,'status',l.status,'billing_cycle',l.billing_cycle,
                    'valid_from',l.valid_from,'valid_until',l.valid_until,'license_code',l.license_code,'updated_at',l.updated_at
                ) x
                from public.network_licenses l
                join public.store_networks n on n.id=l.network_id
                join public.license_plans p on p.id=l.plan_id
                order by l.updated_at desc limit 200
            ) q
        ),'[]'::jsonb),
        'payments',coalesce((
            select jsonb_agg(x order by (x->>'created_at') desc) from (
                select jsonb_build_object(
                    'payment_id',pay.id,'order_id',pay.provider_order_id,'network_id',pay.network_id,
                    'network_name',n.name,'email',u.email,'plan_name',p.name,'billing_cycle',pay.billing_cycle,
                    'amount',pay.amount,'status',pay.status,'provider_status',pay.provider_status,
                    'created_at',pay.created_at,'paid_at',pay.paid_at
                ) x
                from public.license_payments pay
                join public.store_networks n on n.id=pay.network_id
                join public.license_plans p on p.id=pay.plan_id
                left join auth.users u on u.id=pay.requested_by
                order by pay.created_at desc limit 300
            ) q
        ),'[]'::jsonb),
        'events',coalesce((
            select jsonb_agg(x order by (x->>'created_at') desc) from (
                select jsonb_build_object('event_type',e.event_type,'network_id',e.network_id,'email',u.email,'detail',e.detail,'created_at',e.created_at) x
                from public.license_events e left join auth.users u on u.id=e.user_id
                order by e.created_at desc limit 300
            ) q
        ),'[]'::jsonb)
    ) into v_result;
    return v_result;
end;
$$;
revoke all on function public.ldm_developer_license_overview() from public,anon;
grant execute on function public.ldm_developer_license_overview() to authenticated;

-- ------------------------------------------------
-- Kuota toko berdasarkan paket.
-- Existing store tetap hidup; hanya penambahan store aktif baru yang dicegah.
-- ------------------------------------------------
create or replace function public.ldm_license_store_quota_guard()
returns trigger
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
    v_license public.network_licenses%rowtype;
    v_plan public.license_plans%rowtype;
    v_count integer;
    v_valid boolean;
begin
    if new.active is not true then return new; end if;
    if tg_op='UPDATE' and old.active is true then return new; end if;
    if public.ldm_is_license_developer() then return new; end if;

    select * into v_license from public.network_licenses where network_id=new.network_id limit 1;
    v_valid:=v_license.id is not null and v_license.status in ('trialing','active')
             and (v_license.valid_until is null or v_license.valid_until>now());
    if not v_valid then raise exception 'Lisensi aktif diperlukan untuk menambah toko.'; end if;
    select * into strict v_plan from public.license_plans where id=v_license.plan_id;
    select count(*)::int into v_count from public.store_network_stores
    where network_id=new.network_id and active=true;
    if v_count>=v_plan.max_stores then
        raise exception 'Batas toko paket % tercapai (% toko).',v_plan.name,v_plan.max_stores;
    end if;
    return new;
end;
$$;
drop trigger if exists trg_license_store_quota on public.store_network_stores;
create trigger trg_license_store_quota before insert or update of active on public.store_network_stores
for each row execute function public.ldm_license_store_quota_guard();

-- ------------------------------------------------
-- Kuota device berdasarkan distinct client_device_id satu network.
-- Device PENDING boleh terdaftar. Saat diaktifkan/diwariskan, kuota dicek.
-- ------------------------------------------------
create or replace function public.ldm_license_device_quota_guard()
returns trigger
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
    v_network uuid;
    v_license public.network_licenses%rowtype;
    v_plan public.license_plans%rowtype;
    v_count integer;
    v_exists boolean;
    v_valid boolean;
begin
    if new.status<>'active' or new.deleted_at is not null then return new; end if;
    if tg_op='UPDATE' and old.status='active' and old.deleted_at is null then return new; end if;
    if public.ldm_is_license_developer() then return new; end if;

    select sns.network_id into v_network from public.store_network_stores sns
    where sns.store_id=new.store_id and sns.active=true limit 1;
    if v_network is null then return new; end if;

    select exists(
        select 1 from public.devices d
        join public.store_network_stores sns on sns.store_id=d.store_id and sns.active=true
        where sns.network_id=v_network and d.client_device_id=new.client_device_id
          and d.status='active' and d.deleted_at is null
          and (tg_op='INSERT' or d.id<>new.id)
    ) into v_exists;
    if v_exists then return new; end if;

    select * into v_license from public.network_licenses where network_id=v_network limit 1;
    v_valid:=v_license.id is not null and v_license.status in ('trialing','active')
             and (v_license.valid_until is null or v_license.valid_until>now());
    if not v_valid then raise exception 'Lisensi aktif diperlukan untuk mengaktifkan perangkat baru.'; end if;
    select * into strict v_plan from public.license_plans where id=v_license.plan_id;
    select count(distinct d.client_device_id)::int into v_count
    from public.devices d
    join public.store_network_stores sns on sns.store_id=d.store_id and sns.active=true
    where sns.network_id=v_network and d.status='active' and d.deleted_at is null;
    if v_count>=v_plan.max_devices then
        raise exception 'Batas perangkat paket % tercapai (% perangkat).',v_plan.name,v_plan.max_devices;
    end if;
    return new;
end;
$$;
drop trigger if exists trg_license_device_quota on public.devices;
create trigger trg_license_device_quota before insert or update of status,deleted_at on public.devices
for each row execute function public.ldm_license_device_quota_guard();

-- ------------------------------------------------
-- Realtime untuk lisensi/payment agar status UI cepat berubah.
-- ------------------------------------------------
do $$ begin
    if exists(select 1 from pg_publication where pubname='supabase_realtime') then
        if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='network_licenses') then
            alter publication supabase_realtime add table public.network_licenses;
        end if;
        if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='license_payments') then
            alter publication supabase_realtime add table public.license_payments;
        end if;
    end if;
end $$;

insert into public.ldm_system_meta(key,value) values
    ('live_sync_stage','23'),
    ('schema_version','23'),
    ('schema_status','license_billing_ready'),
    ('license_authority','public.network_licenses'),
    ('license_trial_plan','warung-sederhana'),
    ('license_trial_days','14'),
    ('license_payment_provider','midtrans'),
    ('license_scope','store_network'),
    ('license_enforcement','enabled')
on conflict(key) do update set value=excluded.value,updated_at=now();

commit;
