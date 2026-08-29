-- ================================================================
-- LocDailyMar - TAHAP 23.1
-- Lisensi Manual via WhatsApp Developer
-- Baseline: TAHAP 23.0.0
--
-- TUJUAN:
-- 1. Lifetime = 15 device / 8 toko / Rp2.799.000.
-- 2. Trial Warung Sederhana tetap 14 hari.
-- 3. Developer tetap dapat melihat siapa yang memakai trial.
-- 4. Payment Midtrans diganti request manual via WhatsApp.
-- 5. Lisensi HANYA aktif setelah Developer menekan Konfirmasi Pembayaran.
-- ================================================================

begin;

-- ------------------------------------------------
-- 1) Paket final
-- ------------------------------------------------
update public.license_plans
set
    name = 'Warung Kecil',
    monthly_price = 29000,
    yearly_price = 299000,
    lifetime_price = null,
    max_devices = 2,
    max_stores = 1,
    trial_days = 0,
    trial_enabled = false,
    active = true,
    sort_order = 10,
    updated_at = now()
where code = 'warung-kecil';

update public.license_plans
set
    name = 'Warung Sederhana',
    monthly_price = 59000,
    yearly_price = 599000,
    lifetime_price = null,
    max_devices = 4,
    max_stores = 2,
    trial_days = 14,
    trial_enabled = true,
    active = true,
    sort_order = 20,
    updated_at = now()
where code = 'warung-sederhana';

update public.license_plans
set
    name = 'Toko',
    monthly_price = 99000,
    yearly_price = 999000,
    lifetime_price = null,
    max_devices = 8,
    max_stores = 4,
    trial_days = 0,
    trial_enabled = false,
    active = true,
    sort_order = 30,
    updated_at = now()
where code = 'toko';

update public.license_plans
set
    name = 'Lifetime',
    monthly_price = null,
    yearly_price = null,
    lifetime_price = 2799000,
    max_devices = 15,
    max_stores = 8,
    trial_days = 0,
    trial_enabled = false,
    active = true,
    sort_order = 40,
    updated_at = now()
where code = 'lifetime';

-- ------------------------------------------------
-- 2) Pengaturan kontak Developer
-- Nomor WA memakai format internasional TANPA +, spasi, atau tanda '-'.
-- Contoh Indonesia: 6281234567890
-- ------------------------------------------------
create table if not exists public.license_settings (
    id text primary key,
    developer_whatsapp text not null,
    developer_display_name text not null default 'Developer LocDailyMar',
    payment_instruction text,
    active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

insert into public.license_settings(
    id,
    developer_whatsapp,
    developer_display_name,
    payment_instruction,
    active
)
values(
    'default',
    '628XXXXXXXXXX',
    'Developer LocDailyMar',
    'Hubungi Developer melalui WhatsApp. Setelah melakukan pembayaran sesuai instruksi Developer, kirim bukti pembayaran pada chat yang sama.',
    true
)
on conflict(id) do nothing;

alter table public.license_settings enable row level security;
revoke all on public.license_settings from anon, authenticated;

-- ------------------------------------------------
-- 3) Contact RPC
-- ------------------------------------------------
create or replace function public.ldm_license_contact()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
    v_row public.license_settings%rowtype;
begin
    if auth.uid() is null then
        raise exception 'Auth session missing!';
    end if;

    select * into v_row
    from public.license_settings s
    where s.id = 'default'
      and s.active = true
    limit 1;

    if v_row.id is null then
        raise exception 'Kontak Developer belum dikonfigurasi.';
    end if;

    return jsonb_build_object(
        'whatsapp', v_row.developer_whatsapp,
        'developer_name', v_row.developer_display_name,
        'instruction', v_row.payment_instruction
    );
end;
$$;

revoke all on function public.ldm_license_contact() from public, anon;
grant execute on function public.ldm_license_contact() to authenticated;

-- ------------------------------------------------
-- 4) Satu request WhatsApp pending untuk kombinasi network/plan/cycle.
-- ------------------------------------------------
create unique index if not exists license_payments_one_pending_whatsapp
on public.license_payments(network_id, plan_id, billing_cycle)
where provider = 'whatsapp_manual'
  and status = 'pending';

-- ------------------------------------------------
-- 5) Owner membuat request pembayaran manual via WhatsApp.
-- Browser TIDAK dapat menandai payment sebagai paid.
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
    v_plan public.license_plans%rowtype;
    v_existing public.license_payments%rowtype;
    v_payment public.license_payments%rowtype;
    v_contact public.license_settings%rowtype;
    v_cycle text;
    v_amount bigint;
    v_order text;
    v_network_name text;
    v_network_code text;
    v_email text;
begin
    if auth.uid() is null then
        raise exception 'Auth session missing!';
    end if;

    if public.ldm_current_role() <> 'owner' then
        raise exception 'Hanya Owner yang dapat membuat request pembayaran lisensi.';
    end if;

    v_network := public.ldm_current_network_id();
    if v_network is null then
        raise exception 'Network toko aktif belum tersedia.';
    end if;

    v_cycle := lower(btrim(coalesce(p_billing_cycle, '')));
    if v_cycle not in ('monthly', 'yearly', 'lifetime') then
        raise exception 'Billing cycle tidak valid.';
    end if;

    select * into v_plan
    from public.license_plans p
    where p.code = lower(btrim(coalesce(p_plan_code, '')))
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

    if coalesce(v_amount, 0) <= 0 then
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
        raise exception 'Nomor WhatsApp Developer belum valid. Gunakan angka format internasional, contoh 6281234567890.';
    end if;

    -- Kembalikan request pending yang sudah ada agar klik berulang tidak membuat banyak order.
    select * into v_existing
    from public.license_payments pay
    where pay.network_id = v_network
      and pay.plan_id = v_plan.id
      and pay.billing_cycle = v_cycle
      and pay.provider = 'whatsapp_manual'
      and pay.status = 'pending'
    order by pay.created_at desc
    limit 1;

    select n.name, n.code
      into v_network_name, v_network_code
    from public.store_networks n
    where n.id = v_network
    limit 1;

    select u.email into v_email
    from auth.users u
    where u.id = auth.uid()
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
            'owner_email', v_email,
            'developer_whatsapp', v_contact.developer_whatsapp,
            'developer_name', v_contact.developer_display_name,
            'instruction', v_contact.payment_instruction,
            'status', v_existing.status
        );
    end if;

    v_order := (
        'LDM-WA-' ||
        to_char(clock_timestamp() at time zone 'Asia/Makassar', 'YYMMDDHH24MISS') || '-' ||
        upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8))
    );

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
    )
    values(
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
            'channel', 'whatsapp',
            'requested_at', now()
        )
    )
    returning * into v_payment;

    insert into public.license_events(
        network_id,
        user_id,
        event_type,
        detail
    )
    values(
        v_network,
        auth.uid(),
        'whatsapp_payment_requested',
        jsonb_build_object(
            'payment_id', v_payment.id,
            'order_id', v_payment.provider_order_id,
            'plan', v_plan.code,
            'billing_cycle', v_cycle,
            'amount', v_amount
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
        'owner_email', v_email,
        'developer_whatsapp', v_contact.developer_whatsapp,
        'developer_name', v_contact.developer_display_name,
        'instruction', v_contact.payment_instruction,
        'status', v_payment.status
    );
end;
$$;

revoke all on function public.ldm_create_whatsapp_payment_request(text, text)
from public, anon;
grant execute on function public.ldm_create_whatsapp_payment_request(text, text)
to authenticated;

-- ------------------------------------------------
-- 6) Developer mengonfirmasi pembayaran secara manual.
-- Hanya akun di license_developer_admins.
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
    v_activation jsonb;
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
            'status', v_pay.status
        );
    end if;

    if v_pay.status <> 'pending' then
        raise exception 'Hanya payment pending yang dapat dikonfirmasi.';
    end if;

    update public.license_payments
    set
        status = 'paid',
        provider_status = 'confirmed_by_developer',
        payment_type = 'manual_whatsapp',
        paid_at = now(),
        raw_last_notification = coalesce(raw_last_notification, '{}'::jsonb)
            || jsonb_build_object(
                'confirmed_by', auth.uid(),
                'confirmed_at', now(),
                'developer_note', nullif(btrim(coalesce(p_note, '')), '')
            ),
        updated_at = now()
    where id = v_pay.id;

    insert into public.license_events(
        network_id,
        user_id,
        event_type,
        detail
    )
    values(
        v_pay.network_id,
        auth.uid(),
        'whatsapp_payment_confirmed',
        jsonb_build_object(
            'payment_id', v_pay.id,
            'order_id', v_pay.provider_order_id,
            'note', nullif(btrim(coalesce(p_note, '')), '')
        )
    );

    v_activation := public.ldm_activate_license_from_payment(v_pay.id);

    return jsonb_build_object(
        'ok', true,
        'payment_id', v_pay.id,
        'status', 'paid',
        'activation', v_activation
    );
end;
$$;

revoke all on function public.ldm_developer_confirm_whatsapp_payment(uuid, text)
from public, anon;
grant execute on function public.ldm_developer_confirm_whatsapp_payment(uuid, text)
to authenticated;

-- ------------------------------------------------
-- 7) Developer menolak/membatalkan request WhatsApp.
-- ------------------------------------------------
create or replace function public.ldm_developer_reject_whatsapp_payment(
    p_payment_id uuid,
    p_reason text default null
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

    if v_pay.status <> 'pending' then
        raise exception 'Hanya payment pending yang dapat ditolak.';
    end if;

    update public.license_payments
    set
        status = 'cancelled',
        provider_status = 'rejected_by_developer',
        raw_last_notification = coalesce(raw_last_notification, '{}'::jsonb)
            || jsonb_build_object(
                'rejected_by', auth.uid(),
                'rejected_at', now(),
                'reason', nullif(btrim(coalesce(p_reason, '')), '')
            ),
        updated_at = now()
    where id = v_pay.id;

    insert into public.license_events(
        network_id,
        user_id,
        event_type,
        detail
    )
    values(
        v_pay.network_id,
        auth.uid(),
        'whatsapp_payment_rejected',
        jsonb_build_object(
            'payment_id', v_pay.id,
            'order_id', v_pay.provider_order_id,
            'reason', nullif(btrim(coalesce(p_reason, '')), '')
        )
    );

    return jsonb_build_object(
        'ok', true,
        'payment_id', v_pay.id,
        'status', 'cancelled'
    );
end;
$$;

revoke all on function public.ldm_developer_reject_whatsapp_payment(uuid, text)
from public, anon;
grant execute on function public.ldm_developer_reject_whatsapp_payment(uuid, text)
to authenticated;

-- ------------------------------------------------
-- 8) Metadata
-- ------------------------------------------------
insert into public.ldm_system_meta(key, value)
values
    ('license_payment_provider', 'whatsapp_manual'),
    ('license_payment_confirmation', 'developer_manual'),
    ('license_lifetime_price', '2799000'),
    ('license_lifetime_devices', '15'),
    ('license_lifetime_stores', '8'),
    ('license_trial_plan', 'warung-sederhana'),
    ('license_trial_days', '14'),
    ('schema_version', '23.1'),
    ('schema_status', 'license_whatsapp_manual_ready')
on conflict(key) do update set
    value = excluded.value,
    updated_at = now();

commit;

-- ================================================================
-- PENTING - SET NOMOR WA DEVELOPER SETELAH SQL BERHASIL
-- GANTI 6281234567890 DENGAN NOMOR ANDA SENDIRI.
-- ================================================================
-- update public.license_settings
-- set developer_whatsapp = '6281234567890',
--     developer_display_name = 'Nama Developer Anda',
--     updated_at = now()
-- where id = 'default';
