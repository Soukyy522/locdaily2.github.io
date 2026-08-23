# Folder js

Folder ini disiapkan untuk tahap migrasi berikutnya. Untuk menjaga aplikasi tetap identik dengan baseline Tahap 0, JavaScript inline lama belum dipindahkan keluar dari file HTML.

Rencana penggunaan:
- app-config.js untuk konfigurasi frontend public
- auth.js untuk Supabase Auth
- database.js untuk client database
- realtime.js untuk live sync
- service per modul seperti product-service.js dan transaction-service.js

Jangan taruh service_role key, password database, atau secret server di sini.
