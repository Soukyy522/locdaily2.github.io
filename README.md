# LocDailyMar POS

Baseline **Live Sync Tahap 1: GitHub Repository Ready**.

## Arsitektur saat ini

- Frontend: HTML + CSS + JavaScript
- Penyimpanan bisnis: masih `localStorage`
- Shift Management: sudah dihapus
- Absensi: Shift 1 / Shift 2 / Full Day hanya atribut Absensi
- Hosting target: GitHub Pages
- Database target: Supabase PostgreSQL

## Halaman aplikasi
- `Purchase-Order.html`
- `absensi.html`
- `backup & restore.html`
- `barang.html`
- `dashboard.html`
- `eod.html`
- `goods.receipt.html`
- `index.html`
- `kartu-stok.html`
- `kasir.html`
- `laporan.html`
- `pengeluaran.html`
- `retur.html`
- `shift-closing.html`
- `stock-opname.html`
- `supplier.html`

## Struktur repository

```text
/
├── index.html
├── dashboard.html
├── barang.html
├── kasir.html
├── ... halaman aplikasi lainnya
├── js/
├── css/
├── assets/
├── docs/
├── .gitignore
└── .env.example
```

## Keamanan

Jangan commit `service_role` key, password database, JWT secret, token admin, atau credential privat.

## Roadmap

- [x] Tahap 0: baseline dan audit
- [x] Tahap 1: repository GitHub siap
- [ ] Tahap 2: GitHub Pages
- [ ] Tahap 3: Supabase project
- [ ] Tahap 4+: migrasi database bertahap


## Tahap 2 - GitHub Pages
Paket ini siap untuk deployment GitHub Pages dari branch `main` folder root. Setelah deployment, buka `pages-health-check.html`. Live Sync belum aktif pada Tahap 2.


## Tahap 3 - Supabase

Paket ini memiliki client Supabase dasar dan halaman `supabase-connection-test.html`.
Isi Project URL + Publishable Key di `js/supabase-config.js`, jalankan SQL
`supabase/sql/00-stage3-system-meta.sql`, lalu uji koneksi melalui GitHub Pages.

Data bisnis masih menggunakan `localStorage` pada tahap ini.


## Tahap 4 - Cloud Foundation

Database foundation sudah disiapkan melalui:

- `supabase/sql/01-stage4-cloud-foundation.sql`
- `supabase/sql/01-stage4-verify.sql`
- `supabase-stage4-test.html`

Tabel foundation:

- `stores`
- `profiles`
- `devices`

Edit Akun tetap hanya untuk Owner. Supabase Auth dan migrasi data bisnis belum diaktifkan pada Tahap 4.


## Tahap 5 - Supabase Auth Foundation

File baru:

- `js/cloud-auth.js`
- `supabase-stage5-auth-test.html`
- `supabase/sql/02-stage5-auth-foundation.sql`
- `supabase/sql/02-stage5-bootstrap-owner-template.sql`
- `supabase/sql/02-stage5-verify.sql`

Login utama `index.html` belum diganti. Supabase Auth diuji terpisah terlebih dahulu untuk mencegah lockout saat setup.

Edit Akun tetap hanya dapat diakses Owner.


## Tahap 6 - Main Supabase Auth

Login utama sekarang menggunakan Supabase Auth.

Role resmi berasal dari `public.profiles.role`. Nilai role di localStorage hanya dipertahankan sebagai cache kompatibilitas untuk modul lama.

File utama:
- `js/cloud-session.js`
- `js/cloud-session-guard.js`
- `supabase-stage6-auth-authority-test.html`
- `supabase/sql/03-stage6-main-cloud-auth.sql`
- `supabase/sql/03-stage6-link-user-profile-template.sql`
- `supabase/sql/03-stage6-verify.sql`

Edit Akun tetap Owner-only.


## Tahap 7 - Cloud Master Barang

Master Barang sekarang mempunyai backend `public.products` dengan UUID stabil, RLS, soft delete, dan Realtime.

`localStorage.dataBarang` masih dipertahankan sebagai compatibility cache untuk modul lama. Stok masih berupa `legacy_stock_snapshot` sampai tahap ledger stok atomic.

File utama:
- `js/products-service.js`
- `js/products-bootstrap.js`
- `supabase-stage7-products-migration.html`
- `supabase-stage7-realtime-test.html`
- `supabase/sql/04-stage7-products-cloud.sql`
- `supabase/sql/04-stage7-verify.sql`


### Multi User Profile

Tahap 7 memakai template multi-account untuk menghubungkan beberapa Supabase Auth user ke `public.profiles` sekaligus:

- `supabase/sql/04-stage7-link-multiple-user-profiles.sql`


## Tahap 8 - Cloud Transactions + Atomic Stock

Checkout Kasir sekarang menggunakan `ldm_complete_sale()`.
Transaksi, item, pengurangan stok, dan stock movement disimpan dalam satu PostgreSQL transaction.

File utama:
- `js/transactions-service.js`
- `supabase-stage8-transactions-stock-test.html`
- `supabase/sql/05-stage8-transactions-atomic-stock.sql`
- `supabase/sql/05-stage8-verify.sql`

Atomic stock saat ini berlaku untuk SALE Kasir. Inventory flow lain masih dimigrasikan bertahap.


## Tahap 9 - Cloud Absensi

Presensi sekarang memakai `public.attendance`, private Storage untuk foto, Realtime, dan server-side attendance guard untuk transaksi.

Shift tetap hanya label (`Shift 1`, `Shift 2`, `Full Day`). Shift Management tidak digunakan.

File utama:
- `js/attendance-service.js`
- `js/attendance-bootstrap.js`
- `supabase-stage9-attendance-migration.html`
- `supabase-stage9-attendance-test.html`
- `supabase/sql/06-stage9-cloud-attendance.sql`
- `supabase/sql/06-stage9-verify.sql`


## Tahap 10 - Cloud Retur & Stock Opname

Retur dan Stock Opname baru memakai Supabase sebagai authority. Retur approval/cancel dan Stock Opname approval/cancel mengubah `products.legacy_stock_snapshot` bersama `stock_movements` secara atomik. Histori legacy dapat dimigrasikan tanpa menerapkan stok ulang.


## Tahap 11 - Cloud Procurement

Supplier, Purchase Order, dan Goods Receipt sekarang memiliki cloud authority di Supabase. Goods Receipt Accepted memperbarui stok melalui atomic RPC dan ledger `stock_movements`. Legacy PO/GR dimigrasikan sebagai history-only.

File utama:
- `js/procurement-service.js`
- `js/procurement-bootstrap.js`
- `supabase-stage11-procurement-migration.html`
- `supabase-stage11-procurement-test.html`
- `supabase/sql/08-stage11-suppliers-po-goods-receipt.sql`
- `supabase/sql/08-stage11-verify.sql`
