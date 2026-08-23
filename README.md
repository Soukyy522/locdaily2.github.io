# LocDailyMar POS

Baseline **Tahap 1** untuk persiapan GitHub dan migrasi live sync.

## Status
- Hosting target: GitHub Pages.
- Database target: Supabase PostgreSQL.
- Sumber data bisnis saat ini: masih localStorage.

## Halaman utama
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

## Struktur
```text
/
├── index.html
├── dashboard.html
├── ... halaman aplikasi
├── js/
├── css/
├── assets/
├── docs/
├── .gitignore
└── .env.example
```

## Keamanan
Jangan commit service_role key, password database, JWT secret, atau credential privat apa pun ke repository GitHub.
