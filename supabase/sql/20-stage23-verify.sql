-- LocDailyMar TAHAP 23 VERIFY
select key,value from public.ldm_system_meta where key like 'license_%' or key in ('live_sync_stage','schema_version','schema_status') order by key;

select code,name,monthly_price,yearly_price,lifetime_price,max_devices,max_stores,trial_days,trial_enabled,active
from public.license_plans order by sort_order;

select tablename,rowsecurity from pg_tables
where schemaname='public' and tablename in ('license_plans','network_licenses','license_trials','license_payments','license_events','license_developer_admins')
order by tablename;

select trigger_name,event_object_table,action_timing,event_manipulation
from information_schema.triggers
where trigger_name in ('trg_license_store_quota','trg_license_device_quota')
order by trigger_name;

select pubname,schemaname,tablename from pg_publication_tables
where pubname='supabase_realtime' and tablename in ('network_licenses','license_payments')
order by tablename;

-- Jalankan sebagai user aplikasi terautentikasi via halaman license.html untuk menguji context.
-- SQL Editor tidak memiliki auth.uid() user aplikasi, jadi ldm_license_context() tidak dites dari sini.
