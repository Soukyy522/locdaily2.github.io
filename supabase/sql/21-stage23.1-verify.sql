-- LocDailyMar TAHAP 23.1 VERIFY

-- 1. Paket final
select
    code,name,monthly_price,yearly_price,lifetime_price,
    max_devices,max_stores,trial_days,trial_enabled,active
from public.license_plans
order by sort_order;

-- 2. Kontak WA. Pastikan BUKAN placeholder.
select
    id,developer_whatsapp,developer_display_name,
    payment_instruction,active
from public.license_settings
where id='default';

-- 3. Developer admin
select
    u.email,d.user_id,d.created_at
from public.license_developer_admins d
join auth.users u on u.id=d.user_id
order by d.created_at;

-- 4. Trial terbaru. Developer License Center juga dapat melihat data ini.
select
    t.id,u.email,n.name as network_name,p.name as plan_name,
    t.started_at,t.expires_at,t.status
from public.license_trials t
join public.store_networks n on n.id=t.network_id
join public.license_plans p on p.id=t.plan_id
left join auth.users u on u.id=t.started_by
order by t.started_at desc
limit 50;

-- 5. Request payment manual terbaru
select
    pay.id,pay.provider_order_id,pay.provider,p.name as plan_name,
    pay.billing_cycle,pay.amount,pay.status,pay.provider_status,
    u.email,pay.created_at,pay.paid_at
from public.license_payments pay
join public.license_plans p on p.id=pay.plan_id
left join auth.users u on u.id=pay.requested_by
where pay.provider='whatsapp_manual'
order by pay.created_at desc
limit 100;

-- 6. Metadata
select key,value
from public.ldm_system_meta
where key in (
    'license_payment_provider',
    'license_payment_confirmation',
    'license_lifetime_price',
    'license_lifetime_devices',
    'license_lifetime_stores',
    'license_trial_plan',
    'license_trial_days',
    'schema_version',
    'schema_status'
)
order by key;
