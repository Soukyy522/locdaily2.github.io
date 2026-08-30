-- =====================================================================
-- LocDailyMar 23.2 - OPERASIONAL LISENSI DAN PERANGKAT
-- JALANKAN DI PROJECT SUPABASE KHUSUS LISENSI.
-- Pilih satu blok dan ganti UUID contoh sebelum menjalankan.
-- =====================================================================

-- 1. LIHAT SEMUA CUSTOMER/LISENSI
select * from public.license_customer_monitor order by starts_at desc;

-- 2. LIHAT SEMUA PENGGUNA TRIAL
select * from public.license_trial_monitor order by trial_started_at desc;

-- 3. UBAH TRIAL MENJADI WARUNG SEDERHANA BULANAN
-- select public.ldm_convert_trial(
--     'LICENSE_ID_TRIAL',
--     'WARUNG_SEDERHANA',
--     'monthly',
--     1,
--     59000,
--     'INV-2026-TRIAL-001',
--     'Trial dikonversi setelah pembayaran diterima'
-- );

-- 4. UBAH TRIAL MENJADI TOKO TAHUNAN
-- select public.ldm_convert_trial(
--     'LICENSE_ID_TRIAL','TOKO','yearly',1,999000,
--     'INV-2026-TRIAL-002','Trial dikonversi menjadi paket Toko'
-- );

-- 5. PERPANJANG SATU BULAN
-- Jika belum habis, satu bulan ditambahkan dari tanggal akhir lama.
-- Jika sudah habis, satu bulan dihitung dari waktu perpanjangan.
-- select public.ldm_renew_license(
--     'LICENSE_ID_CUSTOMER','monthly',1,59000,
--     'INV-2026-RENEW-001','Perpanjangan satu bulan'
-- );

-- 6. PERPANJANG SATU TAHUN
-- select public.ldm_renew_license(
--     'LICENSE_ID_CUSTOMER','yearly',1,599000,
--     'INV-2026-RENEW-002','Perpanjangan satu tahun'
-- );

-- 7. TANGGUHKAN LISENSI SEMENTARA
-- Data customer tidak dihapus. Aplikasi ditolak saat validasi berikutnya.
-- select public.ldm_set_license_status(
--     'LICENSE_ID_CUSTOMER','suspended','Menunggu pembayaran/perlu pemeriksaan'
-- );

-- 8. AKTIFKAN KEMBALI LISENSI YANG DITANGGUHKAN
-- Lisensi yang sudah kedaluwarsa harus diperpanjang dahulu.
-- select public.ldm_set_license_status(
--     'LICENSE_ID_CUSTOMER','active','Pembayaran telah diterima'
-- );

-- 9. LIHAT PERANGKAT CUSTOMER
-- select
--     a.id activation_id,l.customer_name,l.customer_email,l.plan_code,
--     a.store_ref,a.device_name,a.platform,a.app_version,a.status,
--     a.first_activated_at,a.last_validated_at,a.deactivated_at
-- from public.license_activations a
-- join public.licenses l on l.id=a.license_id
-- where l.id='LICENSE_ID_CUSTOMER'
-- order by a.last_validated_at desc;

-- 10. NONAKTIFKAN PERANGKAT LAMA
-- Gunakan activation_id dari query nomor 9.
-- select public.ldm_admin_deactivate_activation(
--     'ACTIVATION_ID_PERANGKAT'
-- );

-- 11. CEK STATUS SETELAH PERUBAHAN
-- select * from public.license_customer_monitor
-- where id='LICENSE_ID_CUSTOMER';

-- 12. UPDATE ENTITLEMENT PADA PROJECT CLOUD SETELAH PERPANJANGAN
-- BLOK INI DIJALANKAN DI PROJECT CLOUD APLIKASI, BUKAN PROJECT LISENSI.
-- update public.store_license_entitlements
-- set status='active',expires_at='2027-08-30 23:59:59+08',
--     updated_at=now(),note='Perpanjangan diterima'
-- where license_reference='LICENSE_ID_CUSTOMER';
