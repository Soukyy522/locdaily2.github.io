-- =====================================================================
-- SERAH-TERIMA CUSTOMER - jalankan di project Supabase CLOUD APLIKASI.
-- Prasyarat:
-- 1) Seluruh SQL aplikasi sampai Tahap 22 sudah dijalankan.
-- 2) 20-stage23-license-cloud-entitlements.sql sudah dijalankan.
-- 3) Buat/invite Auth User di Authentication > Users terlebih dahulu.
-- 4) Salin license_id, paket, masa akhir, dan kuota dari project LISENSI.
-- =====================================================================

do $$
declare
    -- GANTI 11 NILAI INI
    v_email text := 'customer@email.com';
    v_store_code text := 'TOKO-UTAMA';
    v_store_name text := 'Nama Toko Customer';
    v_username text := 'owner';
    v_display_name text := 'Nama Pemilik';
    v_license_reference uuid := '00000000-0000-0000-0000-000000000000';
    v_plan_code text := 'WARUNG_SEDERHANA';
    v_max_devices integer := 3;
    v_max_stores integer := 1;
    v_is_lifetime boolean := false;
    v_expires_at timestamptz := '2026-09-29 23:59:59+08'; -- Lifetime: isi NULL

    v_user_id uuid; v_store_id uuid; v_network_id uuid; v_existing_store uuid;
begin
    if to_regclass('public.profiles') is null then raise exception 'Tabel public.profiles belum ada. Jalankan SQL aplikasi Tahap 4-22 di project Cloud, bukan project Lisensi.'; end if;
    if to_regclass('public.store_memberships') is null then raise exception 'Tahap 22 belum terpasang: public.store_memberships tidak ditemukan.'; end if;
    if to_regclass('public.store_license_entitlements') is null then raise exception 'Jalankan 20-stage23-license-cloud-entitlements.sql terlebih dahulu.'; end if;

    select id into v_user_id from auth.users where lower(email)=lower(v_email) limit 1;
    if v_user_id is null then raise exception 'Auth User % belum ada. Buat atau Invite dahulu di Authentication > Users.',v_email; end if;

    select store_id into v_existing_store from public.profiles where id=v_user_id;
    if v_existing_store is not null and not exists(select 1 from public.stores where id=v_existing_store and code=upper(v_store_code)) then
        raise exception 'Email % sudah memiliki profile pada toko lain. Jangan memindahkan otomatis; periksa customer secara manual.',v_email;
    end if;

    insert into public.stores(code,name,timezone,currency,status,deleted_at)
    values(upper(trim(v_store_code)),trim(v_store_name),'Asia/Makassar','IDR','active',null)
    on conflict(code) do update set name=excluded.name,status='active',deleted_at=null,updated_at=now()
    returning id into v_store_id;

    insert into public.profiles(id,store_id,username,display_name,role,active,deleted_at)
    values(v_user_id,v_store_id,trim(v_username),trim(v_display_name),'owner',true,null)
    on conflict(id) do update set username=excluded.username,display_name=excluded.display_name,role='owner',active=true,deleted_at=null,updated_at=now();

    insert into public.store_networks(code,name,active,created_by,deleted_at)
    values('NET-'||upper(trim(v_store_code)),trim(v_store_name)||' Network',true,v_user_id,null)
    on conflict(code) do update set name=excluded.name,active=true,deleted_at=null,updated_at=now()
    returning id into v_network_id;

    insert into public.store_license_entitlements(network_id,license_reference,plan_code,status,max_devices,max_stores,is_lifetime,expires_at,note)
    values(v_network_id,v_license_reference,upper(v_plan_code),'active',v_max_devices,v_max_stores,v_is_lifetime,
           case when v_is_lifetime then null else v_expires_at end,'Dibuat saat onboarding customer')
    on conflict(network_id) do update set license_reference=excluded.license_reference,plan_code=excluded.plan_code,status='active',
        max_devices=excluded.max_devices,max_stores=excluded.max_stores,is_lifetime=excluded.is_lifetime,
        expires_at=excluded.expires_at,updated_at=now(),note=excluded.note;

    -- Entitlement dibuat sebelum toko dimasukkan ke network karena trigger kuota
    -- langsung memeriksa lisensi pada setiap penambahan cabang.
    insert into public.store_network_stores(network_id,store_id,is_primary,active)
    values(v_network_id,v_store_id,true,true)
    on conflict(store_id) do update set network_id=excluded.network_id,is_primary=true,active=true;

    insert into public.store_memberships(user_id,store_id,role,active,is_default,invited_by)
    values(v_user_id,v_store_id,'owner',true,true,v_user_id)
    on conflict(user_id,store_id) do update set role='owner',active=true,is_default=true,updated_at=now();

    raise notice 'ONBOARDING SUKSES | user_id=% | store_id=% | Store Code=% | network_id=%',v_user_id,v_store_id,upper(v_store_code),v_network_id;
end$$;

-- HASIL SERAH-TERIMA (UUID internal tidak perlu diketik customer)
select u.email,p.display_name,p.role,s.id store_uuid,s.code store_code,s.name store_name,n.id network_id,e.plan_code,e.max_devices,e.max_stores,e.status,e.expires_at,e.is_lifetime
from auth.users u join public.profiles p on p.id=u.id join public.stores s on s.id=p.store_id
join public.store_network_stores sns on sns.store_id=s.id join public.store_networks n on n.id=sns.network_id
join public.store_license_entitlements e on e.network_id=n.id
where lower(u.email)=lower('customer@email.com'); -- GANTI EMAIL
