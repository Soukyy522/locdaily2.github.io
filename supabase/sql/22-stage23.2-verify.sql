-- ================================================================
-- LocDailyMar - TAHAP 23.2 VERIFY
-- ================================================================

-- 1) Paket, harga, kuota, feature codes
select
    code,
    name,
    monthly_price,
    yearly_price,
    lifetime_price,
    max_devices,
    max_stores,
    trial_days,
    trial_enabled,
    feature_codes
from public.license_plans
where active=true
order by sort_order;

-- 2) Nomor WhatsApp Developer. Pastikan bukan placeholder.
select
    id,
    developer_whatsapp,
    developer_display_name,
    payment_instruction,
    active
from public.license_settings
where id='default';

-- 3) Developer admin
select
    u.email,
    d.user_id,
    d.created_at
from public.license_developer_admins d
join auth.users u on u.id=d.user_id
order by d.created_at;

-- 4) Manual key table + RLS
select schemaname,tablename,rowsecurity
from pg_tables
where schemaname='public'
  and tablename in ('license_activation_keys','network_licenses','license_payments');

-- 5) Key terbaru. Raw key memang TIDAK ada di tabel.
select
    k.id,
    n.code as network_code,
    u.email as owner_email,
    p.name as plan_name,
    k.billing_cycle,
    k.key_hint,
    k.status,
    k.issued_at,
    k.activated_at,
    k.source_payment_id
from public.license_activation_keys k
join public.store_networks n on n.id=k.network_id
join public.license_plans p on p.id=k.plan_id
left join auth.users u on u.id=k.owner_user_id
order by k.issued_at desc
limit 100;

-- 6) Lisensi efektif. Jika valid_until sudah lewat, context berikut
-- akan mengubah status menjadi expired saat dipanggil oleh user terkait.
select
    n.code as network_code,
    p.name as plan_name,
    l.status,
    l.billing_cycle,
    l.license_code,
    l.valid_from,
    l.valid_until,
    case
        when l.billing_cycle='lifetime' then true
        when l.status in ('active','trialing') and l.valid_until>now() then true
        else false
    end as effectively_valid
from public.network_licenses l
join public.store_networks n on n.id=l.network_id
join public.license_plans p on p.id=l.plan_id
order by l.updated_at desc;

-- 7) Trial terbaru agar Developer tahu siapa yang memakai trial.
select
    t.id,
    u.email,
    n.code as network_code,
    p.name as plan_name,
    t.started_at,
    t.expires_at,
    t.status
from public.license_trials t
join public.store_networks n on n.id=t.network_id
join public.license_plans p on p.id=t.plan_id
left join auth.users u on u.id=t.started_by
order by t.started_at desc
limit 100;

-- 8) Payment WhatsApp
select
    pay.provider_order_id,
    u.email,
    n.code as network_code,
    p.name as plan_name,
    pay.billing_cycle,
    pay.amount,
    pay.status,
    pay.provider_status,
    pay.created_at,
    pay.paid_at
from public.license_payments pay
join public.store_networks n on n.id=pay.network_id
join public.license_plans p on p.id=pay.plan_id
left join auth.users u on u.id=pay.requested_by
where pay.provider='whatsapp_manual'
order by pay.created_at desc
limit 100;

-- 9) Metadata
select key,value
from public.ldm_system_meta
where key in (
    'live_sync_stage',
    'schema_version',
    'schema_status',
    'license_activation_mode',
    'license_guard_mode',
    'license_feature_gating',
    'license_expiry_mode',
    'license_lifetime_price',
    'license_lifetime_devices',
    'license_lifetime_stores',
    'license_trial_plan',
    'license_trial_days'
)
order by key;
