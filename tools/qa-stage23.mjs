import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),"..");
const failures=[];
const required=[
  "license.html",
  "js/license-config.js",
  "js/license-client.js",
  "js/security-hardening.js",
  "js/global-system-navigation.js",
  "license-server/supabase/config.toml",
  "license-server/supabase/migrations/20260829000100_license_authority.sql",
  "license-server/supabase/functions/ldm-license/index.ts",
  "license-server/SQL-ADMIN-4-PAKET-COPY-PASTE.sql",
  "tools/generate-license-signing-key.mjs",
  "docs/TAHAP-23-LISENSI-PAKET-BERBAYAR.md"
];
for(const file of required){
  if(!fs.existsSync(path.join(root,file)))failures.push(`File tidak ditemukan: ${file}`);
}

for(const file of ["js/license-config.js","js/license-client.js","js/security-hardening.js","js/global-system-navigation.js","service-worker.js"]){
  try{new vm.Script(fs.readFileSync(path.join(root,file),"utf8"),{filename:file})}
  catch(error){failures.push(`${file}: ${error.message}`)}
}

const read=file=>fs.readFileSync(path.join(root,file),"utf8");
const sql=read("license-server/supabase/migrations/20260829000100_license_authority.sql");
const edge=read("license-server/supabase/functions/ldm-license/index.ts");
const client=read("js/license-client.js");
const config=read("js/license-config.js");
const guard=read("js/security-hardening.js");
const nav=read("js/global-system-navigation.js");
const sw=read("service-worker.js");
const licensePage=read("license.html");

const markers=[
  [sql,"create table if not exists public.license_plans","Tabel paket"],
  [sql,"create table if not exists public.licenses","Tabel lisensi"],
  [sql,"create table if not exists public.license_activations","Tabel aktivasi"],
  [sql,"WARUNG_KECIL', 'Warung Kecil', 1, 1, 1, false","Paket Warung Kecil"],
  [sql,"WARUNG_SEDERHANA', 'Warung Sederhana', 3, 1, 3, false","Paket Warung Sederhana"],
  [sql,"TOKO', 'Toko', 10, 5, 7, false","Paket Toko"],
  [sql,"LIFETIME', 'Lifetime', 15, 8, 14, true","Paket Lifetime"],
  [sql,"is_lifetime boolean not null default false","Kolom Lifetime"],
  [sql,"LIFETIME_LICENSE_CANNOT_EXPIRE","Proteksi expiry Lifetime"],
  [sql,"create function public.ldm_start_trial","RPC mulai trial"],
  [sql,"interval '14 days'","Durasi trial 14 hari"],
  [sql,"create or replace view public.license_trial_monitor","Monitoring trial developer"],
  [sql,"create function public.ldm_convert_trial","Konversi trial berbayar"],
  [sql,"create function public.ldm_renew_license","Perpanjangan lisensi"],
  [sql,"ldm_issue_license","Penerbitan lisensi"],
  [sql,"ldm_license_activate","RPC aktivasi"],
  [sql,"ldm_license_validate","RPC validasi"],
  [sql,"enable row level security","RLS"],
  [sql,"revoke all on table public.licenses from anon, authenticated","Pencabutan akses tabel"],
  [edge,"LDM_LICENSE_PRIVATE_JWK","Private signing key"],
  [edge,"LDM_LICENSE_ALLOWED_ORIGINS","Allowlist origin"],
  [edge,"TOO_MANY_ATTEMPTS","Rate limit"],
  [edge,'{ name: "ECDSA", hash: "SHA-256" }',"Tanda tangan ECDSA"],
  [edge,'action === "start_trial"',"Endpoint trial otomatis"],
  [client,"LICENSE_OFFLINE_GRACE_EXPIRED","Offline grace"],
  [client,"cached.isLifetime!==true","Lifetime melewati pemeriksaan expiry"],
  [client,"verifyCertificate","Verifikasi sertifikat"],
  [client,"async function startTrial","Client trial"],
  [client,'"multi-store.html":"multi_store"',"Feature gate multi-toko"],
  [config,"enabled: false","Fail-safe sebelum konfigurasi"],
  [guard,"bootLicenseGuard","Global license guard"],
  [nav,'feature:"multi_store"',"Navigasi berbasis paket"],
  [sw,'APP_VERSION = "23.1.0"',"Versi PWA"],
  [sw,'"./license.html"',"Cache halaman aktivasi"]
  ,[licensePage,'<h2>Lifetime</h2>',"Kartu paket Lifetime"]
  ,[licensePage,'15 perangkat · 8 toko · offline 14 hari',"Batas Lifetime pada halaman aktivasi"]
  ,[licensePage,'id="trialForm"',"Form trial 14 hari"]
];
for(const [content,marker,label] of markers){
  if(!content.includes(marker))failures.push(`${label} tidak ditemukan.`);
}

const operationalPages=[
  "index.html","dashboard.html","absensi.html","kasir.html","barang.html","kartu-stok.html",
  "stock-opname.html","multi-store.html","supplier.html","Purchase-Order.html","goods.receipt.html",
  "retur.html","laporan.html","pengeluaran.html","shift-closing.html","eod.html","backup & restore.html",
  "pwa-settings.html","recovery-center.html","qa-security-performance.html","account-management.html",
  "device-management.html","device-access.html","cloud-control-center.html"
];
for(const file of operationalPages){
  const content=read(file);
  if(!content.includes("js/security-hardening.js"))failures.push(`${file}: global license bootstrap tidak termuat.`);
}

if(/LDM_LICENSE_PRIVATE_JWK\s*[:=]\s*["']?\{[^\n]*"d"/i.test(config+client+read("license.html"))){
  failures.push("Private JWK terdeteksi pada file browser.");
}
if(!read("VERSION.txt").trim().startsWith("23.1"))failures.push("VERSION.txt belum 23.1.");

if(failures.length){
  console.error(`TAHAP 23 QA: FAIL ${failures.length}`);
  failures.forEach(item=>console.error(`- ${item}`));
  process.exit(1);
}
console.log(`TAHAP 23 QA: PASS (${operationalPages.length} halaman operasional dilindungi)`);
