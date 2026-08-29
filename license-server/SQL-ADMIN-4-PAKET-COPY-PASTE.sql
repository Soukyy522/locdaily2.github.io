-- LocDailyMar 23.1 - Query administrasi 4 paket
-- Jalankan pada SQL Editor PROJECT LISENSI, bukan project toko.

-- ================================================================
-- 1. CEK EMPAT PAKET
-- ================================================================
select code, name, max_devices, max_stores, offline_grace_days, is_lifetime, active
from public.license_plans
order by case code
    when 'WARUNG_KECIL' then 1
    when 'WARUNG_SEDERHANA' then 2
    when 'TOKO' then 3
    when 'LIFETIME' then 4
    else 99
end;

-- ================================================================
-- 2. TERBITKAN WARUNG KECIL - 1 TAHUN
-- ================================================================
select * from public.ldm_issue_license(
    p_customer_name := 'Warung Maju',
    p_customer_email := 'pemilik@example.com',
    p_plan_code := 'WARUNG_KECIL',
    p_expires_at := now() + interval '1 year',
    p_note := 'Pembayaran lunas'
);

-- ================================================================
-- 3. TERBITKAN WARUNG SEDERHANA - 1 TAHUN
-- ================================================================
select * from public.ldm_issue_license(
    p_customer_name := 'Warung Sejahtera',
    p_customer_email := 'owner@example.com',
    p_plan_code := 'WARUNG_SEDERHANA',
    p_expires_at := now() + interval '1 year',
    p_note := 'Pembayaran lunas'
);

-- ================================================================
-- 4. TERBITKAN TOKO - 1 TAHUN
-- ================================================================
select * from public.ldm_issue_license(
    p_customer_name := 'Toko Sentosa',
    p_customer_email := 'owner@example.com',
    p_plan_code := 'TOKO',
    p_expires_at := now() + interval '1 year',
    p_note := 'Pembayaran lunas'
);

-- ================================================================
-- 5. TERBITKAN LIFETIME - TANPA TANGGAL KEDALUWARSA
-- ================================================================
select * from public.ldm_issue_license(
    p_customer_name := 'Toko Abadi',
    p_customer_email := 'owner@example.com',
    p_plan_code := 'LIFETIME',
    p_expires_at := null,
    p_note := 'Lisensi Lifetime sekali bayar'
);

-- ================================================================
-- 6. LIHAT LISENSI DAN PEMAKAIAN SLOT
-- ================================================================
select
    l.id,
    l.key_prefix || '…' as license_key_masked,
    l.customer_name,
    l.customer_email,
    l.plan_code,
    l.status,
    l.is_lifetime,
    case when l.is_lifetime then 'Lifetime' else l.expires_at::text end as masa_aktif,
    count(a.id) filter (where a.status = 'active') as active_devices,
    count(distinct a.store_ref) filter (where a.status = 'active') as active_stores
from public.licenses l
left join public.license_activations a on a.license_id = l.id
group by l.id
order by l.created_at desc;

-- ================================================================
-- 7. LIHAT PERANGKAT SATU LISENSI
-- ================================================================
select id, store_ref, device_name, platform, app_version, status,
       first_activated_at, last_validated_at, deactivated_at
from public.license_activations
where license_id = 'GANTI-DENGAN-UUID-LISENSI'
order by first_activated_at;

-- ================================================================
-- 8. BEKUKAN SEMENTARA
-- ================================================================
select public.ldm_set_license_status(
    'GANTI-DENGAN-UUID-LISENSI',
    'suspended',
    'Menunggu konfirmasi'
);

-- ================================================================
-- 9. AKTIFKAN KEMBALI
-- ================================================================
select public.ldm_set_license_status(
    'GANTI-DENGAN-UUID-LISENSI',
    'active',
    'Lisensi diaktifkan kembali'
);

-- ================================================================
-- 10. CABUT LISENSI
-- ================================================================
select public.ldm_set_license_status(
    'GANTI-DENGAN-UUID-LISENSI',
    'revoked',
    'Lisensi dibatalkan'
);

-- ================================================================
-- 11. BEBASKAN SATU SLOT PERANGKAT
-- ================================================================
update public.license_activations
set status = 'deactivated', deactivated_at = now()
where id = 'GANTI-DENGAN-UUID-AKTIVASI';

-- ================================================================
-- 12. PERPANJANG PAKET NON-LIFETIME SATU TAHUN
-- ================================================================
select public.ldm_renew_license(
    p_license_id := 'GANTI-DENGAN-UUID-LISENSI',
    p_new_expires_at := now() + interval '1 year',
    p_note := 'Perpanjangan diterima'
);

-- ================================================================
-- 13. MONITOR SEMUA PENGGUNA TRIAL
-- ================================================================
select *
from public.license_trial_monitor
order by trial_started_at desc;

-- Hanya trial yang masih aktif:
select *
from public.license_trial_monitor
where trial_state = 'active'
order by trial_ends_at;

-- ================================================================
-- 14. KONVERSI TRIAL MENJADI WARUNG SEDERHANA BERBAYAR 1 TAHUN
-- ================================================================
select public.ldm_convert_trial(
    p_license_id := 'GANTI-DENGAN-UUID-LISENSI-TRIAL',
    p_target_plan_code := 'WARUNG_SEDERHANA',
    p_expires_at := now() + interval '1 year',
    p_note := 'Pembayaran paket Warung Sederhana diterima'
);

-- ================================================================
-- 15. KONVERSI TRIAL MENJADI LIFETIME
-- ================================================================
select public.ldm_convert_trial(
    p_license_id := 'GANTI-DENGAN-UUID-LISENSI-TRIAL',
    p_target_plan_code := 'LIFETIME',
    p_expires_at := null,
    p_note := 'Pembayaran paket Lifetime diterima'
);
