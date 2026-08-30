-- =====================================================================
-- LocDailyMar 23.2 - ADMIN DASHBOARD SECURITY PATCH
-- Jalankan di project Supabase KHUSUS LISENSI.
-- Menambah audit developer dan RPC penonaktifan perangkat.
-- =====================================================================

begin;

create table if not exists public.license_admin_audit(
    id bigint generated always as identity primary key,
    actor_user_id uuid,
    actor_email text,
    action text not null,
    license_id uuid references public.licenses(id) on delete set null,
    activation_id uuid references public.license_activations(id) on delete set null,
    detail jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now()
);

create index if not exists license_admin_audit_created_idx
on public.license_admin_audit(created_at desc);

alter table public.license_admin_audit enable row level security;
revoke all on public.license_admin_audit from anon,authenticated;
revoke all on sequence public.license_admin_audit_id_seq from anon,authenticated;
grant select,insert on public.license_admin_audit to service_role;
grant usage,select on sequence public.license_admin_audit_id_seq to service_role;

create or replace function public.ldm_set_license_status(
    p_license_id uuid,p_status text,p_reason text default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_status text:=lower(trim(p_status)); v_license public.licenses%rowtype;
begin
    if v_status not in('active','suspended','revoked','expired') then raise exception 'INVALID_LICENSE_STATUS'; end if;
    select * into v_license from public.licenses where id=p_license_id for update;
    if not found then raise exception 'LICENSE_NOT_FOUND'; end if;
    if v_license.is_lifetime and v_status='expired' then raise exception 'LIFETIME_LICENSE_CANNOT_EXPIRE'; end if;
    if v_status='active' and not v_license.is_lifetime and now()>=v_license.expires_at then
        raise exception 'LICENSE_RENEWAL_REQUIRED';
    end if;
    update public.licenses set status=v_status,status_reason=nullif(trim(p_reason),''),updated_at=now()
    where id=p_license_id;
    if v_status in('revoked','expired') then
        update public.license_activations set status='revoked',deactivated_at=now()
        where license_id=p_license_id and status='active';
    end if;
    return jsonb_build_object('ok',true,'license_id',p_license_id,'status',v_status,'reason',nullif(trim(p_reason),''));
end;$$;

create or replace function public.ldm_admin_deactivate_activation(p_activation_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v public.license_activations%rowtype;
begin
    update public.license_activations
    set status='deactivated',deactivated_at=now(),last_validated_at=now()
    where id=p_activation_id and status='active'
    returning * into v;
    if not found then raise exception 'ACTIVE_ACTIVATION_NOT_FOUND'; end if;
    return jsonb_build_object('ok',true,'activation_id',v.id,'license_id',v.license_id,
        'status',v.status,'store_ref',v.store_ref,'device_name',v.device_name,'deactivated_at',v.deactivated_at);
end;$$;

revoke all on function public.ldm_set_license_status(uuid,text,text) from public,anon,authenticated;
revoke all on function public.ldm_admin_deactivate_activation(uuid) from public,anon,authenticated;
grant execute on function public.ldm_set_license_status(uuid,text,text) to service_role;
grant execute on function public.ldm_admin_deactivate_activation(uuid) to service_role;

commit;

select 'license_admin_dashboard_ready' status;
