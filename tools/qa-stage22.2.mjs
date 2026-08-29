import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import {fileURLToPath} from "node:url";

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),"..");
const targets=["multi-store.html","pwa-settings.html","recovery-center.html","qa-security-performance.html"];
const required=[...targets,"css/system-pages-shared-theme.css","js/shared-system-theme.js","js/global-system-navigation.js","service-worker.js","docs/PATCH-22.2-TEMA-HALAMAN-SISTEM.md"];
const failures=[];

for(const file of required){if(!fs.existsSync(path.join(root,file)))failures.push(`File tidak ditemukan: ${file}`)}
for(const file of ["js/shared-system-theme.js","js/global-system-navigation.js","service-worker.js"]){
    try{new vm.Script(fs.readFileSync(path.join(root,file),"utf8"),{filename:file})}
    catch(error){failures.push(`${file}: ${error.message}`)}
}

for(const file of targets){
    const html=fs.readFileSync(path.join(root,file),"utf8");
    const markers=["ldm-system-page","ldm-shared-header","data-ldm-menu-toggle","data-ldm-theme-open","data-ldm-brand-title","data-ldm-brand-subtitle","system-pages-shared-theme.css?v=22.2","global-system-navigation.js?v=22.2","shared-system-theme.js?v=22.2"];
    for(const marker of markers){if(!html.includes(marker))failures.push(`${file}: marker tidak ada: ${marker}`)}
    for(const match of html.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/gi)){
        if(!match[1].trim())continue;
        try{new vm.Script(match[1],{filename:`${file}:inline`})}
        catch(error){failures.push(`${file}: ${error.message}`)}
    }
}

const theme=fs.readFileSync(path.join(root,"js/shared-system-theme.js"),"utf8");
for(const marker of ["headerConfig","BroadcastChannel","storage","logoData","darkMode","ldm-theme-changed"]){
    if(!theme.includes(marker))failures.push(`Theme manager belum memiliki: ${marker}`);
}

const css=fs.readFileSync(path.join(root,"css/system-pages-shared-theme.css"),"utf8");
for(const marker of ["@media(max-width:899px)","@media(max-width:620px)",".ldm-theme-modal",".ldm-shared-header","body.dark-mode"]){
    if(!css.includes(marker))failures.push(`CSS bersama belum memiliki: ${marker}`);
}

const sw=fs.readFileSync(path.join(root,"service-worker.js"),"utf8");
for(const marker of ['APP_VERSION = "22.2.0"','css/system-pages-shared-theme.css','js/shared-system-theme.js']){
    if(!sw.includes(marker))failures.push(`Service Worker belum memiliki: ${marker}`);
}

if(failures.length){
    console.error(`PATCH 22.2 QA: FAIL ${failures.length}`);
    failures.forEach(item=>console.error(`- ${item}`));
    process.exit(1);
}
console.log("PATCH 22.2 QA: PASS (4 halaman tema terhubung)");
