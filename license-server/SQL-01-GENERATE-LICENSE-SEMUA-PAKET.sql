-- =====================================================================
-- LocDailyMar 23.2 - GENERATE LICENSE KEY MANUAL UNTUK SEMUA PAKET
-- JALANKAN DI PROJECT SUPABASE KHUSUS LISENSI.
--
-- Cara pakai:
-- 1. Pilih hanya SATU blok paket.
-- 2. Ganti data customer, Store Code, invoice, dan harga bila diperlukan.
-- 3. Jalankan blok tersebut.
-- 4. Simpan license_id dan license_key dari hasil query.
-- License Key asli hanya ditampilkan saat pertama dibuat.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1A. WARUNG KECIL BULANAN
-- Harga: Rp29.000 | 1 perangkat | 1 toko | 1 bulan
-- ---------------------------------------------------------------------
select * from public.ldm_issue_license(
    'NAMA CUSTOMER',
    'customer@email.com',
    '6281234567890',
    'WARUNG_KECIL',
    'monthly',
    1,
    29000,
    'TOKO-UTAMA',
    'INV-2026-001',
    'Warung Kecil bulanan - pembayaran WhatsApp'
);

-- ---------------------------------------------------------------------
-- 1B. WARUNG KECIL TAHUNAN
-- Harga: Rp299.000 | 1 perangkat | 1 toko | 1 tahun
-- HAPUS tanda -- di awal query sebelum menjalankan.
-- ---------------------------------------------------------------------
-- select * from public.ldm_issue_license(
--     'NAMA CUSTOMER','customer@email.com','6281234567890',
--     'WARUNG_KECIL','yearly',1,299000,
--     'TOKO-UTAMA','INV-2026-002','Warung Kecil tahunan'
-- );

-- ---------------------------------------------------------------------
-- 2A. WARUNG SEDERHANA BULANAN
-- Harga: Rp59.000 | 3 perangkat | 1 toko | 1 bulan
-- ---------------------------------------------------------------------
-- select * from public.ldm_issue_license(
--     'NAMA CUSTOMER','customer@email.com','6281234567890',
--     'WARUNG_SEDERHANA','monthly',1,59000,
--     'TOKO-UTAMA','INV-2026-003','Warung Sederhana bulanan'
-- );

-- ---------------------------------------------------------------------
-- 2B. WARUNG SEDERHANA TAHUNAN
-- Harga: Rp599.000 | 3 perangkat | 1 toko | 1 tahun
-- ---------------------------------------------------------------------
-- select * from public.ldm_issue_license(
--     'NAMA CUSTOMER','customer@email.com','6281234567890',
--     'WARUNG_SEDERHANA','yearly',1,599000,
--     'TOKO-UTAMA','INV-2026-004','Warung Sederhana tahunan'
-- );

-- ---------------------------------------------------------------------
-- 3A. TOKO BULANAN
-- Harga: Rp99.000 | 10 perangkat | 5 toko | 1 bulan
-- ---------------------------------------------------------------------
-- select * from public.ldm_issue_license(
--     'NAMA CUSTOMER','customer@email.com','6281234567890',
--     'TOKO','monthly',1,99000,
--     'TOKO-UTAMA','INV-2026-005','Paket Toko bulanan'
-- );

-- ---------------------------------------------------------------------
-- 3B. TOKO TAHUNAN
-- Harga: Rp999.000 | 10 perangkat | 5 toko | 1 tahun
-- ---------------------------------------------------------------------
-- select * from public.ldm_issue_license(
--     'NAMA CUSTOMER','customer@email.com','6281234567890',
--     'TOKO','yearly',1,999000,
--     'TOKO-UTAMA','INV-2026-006','Paket Toko tahunan'
-- );

-- ---------------------------------------------------------------------
-- 4. LIFETIME
-- Harga: Rp3.499.000 | 15 perangkat | 8 toko | tidak kedaluwarsa
-- ---------------------------------------------------------------------
-- select * from public.ldm_issue_license(
--     'NAMA CUSTOMER','customer@email.com','6281234567890',
--     'LIFETIME','lifetime',1,3499000,
--     'TOKO-UTAMA','INV-2026-007','Paket Lifetime'
-- );

-- ---------------------------------------------------------------------
-- CEK HASIL TERBARU. License Key tetap disamarkan pada monitoring.
-- ---------------------------------------------------------------------
select * from public.license_customer_monitor order by starts_at desc;
