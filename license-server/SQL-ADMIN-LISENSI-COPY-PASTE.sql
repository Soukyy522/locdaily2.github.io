-- =====================================================================
-- ADMIN MANUAL LISENSI - jalankan di project Supabase KHUSUS LISENSI.
-- Salin SATU blok sesuai pekerjaan. Ganti semua teks CONTOH.
-- License Key hanya tampil saat dibuat; simpan aman sebelum menutup hasil.
-- =====================================================================

-- 1A. WARUNG KECIL BULANAN - Rp29.000
select * from public.ldm_issue_license(
  'NAMA CUSTOMER','customer@email.com','6281234567890',
  'WARUNG_KECIL','monthly',1,29000,'TOKO-UTAMA','INV-2026-001','Pembayaran via WhatsApp'
);

-- 1B. WARUNG SEDERHANA TAHUNAN - Rp599.000
-- select * from public.ldm_issue_license(
--   'NAMA CUSTOMER','customer@email.com','6281234567890',
--   'WARUNG_SEDERHANA','yearly',1,599000,'TOKO-UTAMA','INV-2026-002','Pembayaran via WhatsApp'
-- );

-- 1C. TOKO TAHUNAN - Rp999.000
-- select * from public.ldm_issue_license(
--   'NAMA CUSTOMER','customer@email.com','6281234567890',
--   'TOKO','yearly',1,999000,'TOKO-UTAMA','INV-2026-003','Pembayaran via WhatsApp'
-- );

-- 1D. LIFETIME - Rp3.499.000, 15 perangkat, 8 toko
-- select * from public.ldm_issue_license(
--   'NAMA CUSTOMER','customer@email.com','6281234567890',
--   'LIFETIME','lifetime',1,3499000,'TOKO-UTAMA','INV-2026-004','Lifetime'
-- );

-- 2. LIHAT SEMUA CUSTOMER (key tetap disamarkan)
select * from public.license_customer_monitor order by starts_at desc;

-- 3. PANTAU SIAPA YANG MEMAKAI TRIAL 14 HARI
select * from public.license_trial_monitor order by trial_started_at desc;

-- 4. UBAH TRIAL MENJADI WARUNG SEDERHANA BULANAN
-- Ganti UUID dari hasil license_trial_monitor.
-- select public.ldm_convert_trial(
--   '00000000-0000-0000-0000-000000000000','WARUNG_SEDERHANA','monthly',1,59000,'INV-2026-005','Pembayaran dikonfirmasi'
-- );

-- 5. PERPANJANG 1 BULAN. Jika belum habis, ditambah dari tanggal akhir lama.
-- select public.ldm_renew_license(
--   '00000000-0000-0000-0000-000000000000','monthly',1,59000,'INV-2026-006','Perpanjangan via WhatsApp'
-- );

-- 6. TANGGUHKAN / AKTIFKAN LAGI
-- select public.ldm_set_license_status('00000000-0000-0000-0000-000000000000','suspended','Menunggu pembayaran');
-- select public.ldm_set_license_status('00000000-0000-0000-0000-000000000000','active','Pembayaran diterima');

-- 7. LIHAT PERANGKAT AKTIF CUSTOMER
-- select a.id activation_id,l.customer_name,l.plan_code,a.store_ref,a.device_name,a.platform,a.app_version,a.status,a.last_validated_at
-- from public.license_activations a join public.licenses l on l.id=a.license_id
-- where l.id='00000000-0000-0000-0000-000000000000'
-- order by a.last_validated_at desc;

-- 8. NONAKTIFKAN PERANGKAT LAMA DAN TAMPILKAN HASIL (tidak menghasilkan "No rows" bila UUID benar)
-- with changed as(
--   update public.license_activations
--   set status='deactivated',deactivated_at=now()
--   where id='00000000-0000-0000-0000-000000000000' and status='active'
--   returning id,status,store_ref,device_name,deactivated_at
-- ) select * from changed;

-- 9. CARI ERROR TERBARU BERDASARKAN Request ID DARI license.html
-- select request_id,action,outcome,reason,detail,created_at
-- from public.license_validation_events
-- where request_id='00000000-0000-0000-0000-000000000000'
-- order by created_at desc;
