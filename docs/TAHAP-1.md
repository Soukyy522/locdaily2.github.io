# Tahap 1 - GitHub Repository

## Tujuan
Menjadikan baseline LocDailyMar siap ditempatkan di GitHub tanpa mengubah logika bisnis.

## Sudah disiapkan
- Semua halaman HTML tetap berada di root agar navigasi relatif tetap bekerja.
- index.html tetap di root, cocok untuk GitHub Pages.
- Folder js/, css/, assets/, dan docs/ disiapkan untuk refactor bertahap.
- .gitignore dibuat.
- .env.example dibuat tanpa secret.
- Struktur dan link lokal diperiksa.
- Inline JavaScript diperiksa menggunakan node --check.

## Yang belum dilakukan pada Tahap 1
- Belum membuat Supabase project.
- Belum memindahkan localStorage ke cloud.
- Belum mengaktifkan GitHub Pages.
- Belum menaruh secret/API admin ke repository.

## Aturan repository
1. Jangan commit password database.
2. Jangan commit Supabase service_role key.
3. Jangan mengubah nama file HTML tanpa memperbarui semua link.
4. Gunakan commit kecil per fitur.
5. Simpan ZIP baseline Tahap 0 di luar repository sebagai backup.
