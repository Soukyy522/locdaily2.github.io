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
