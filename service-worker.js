"use strict";

const CACHE_VERSION = "ldm-stage16-shell-v1";
const RUNTIME_CACHE = "ldm-stage16-runtime-v1";
const SUPABASE_CDN = "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2";

const APP_SHELL = [
    "./kasir.html",
    "./js/supabase-config.js",
    "./js/supabase-client.js",
    "./js/offline-queue.js",
    "./js/cloud-auth.js",
    "./js/cloud-session.js",
    "./js/cloud-session-guard.js",
    "./js/products-service.js",
    "./js/products-bootstrap.js",
    "./js/transactions-service.js",
    "./js/attendance-service.js",
    "./js/attendance-bootstrap.js",
    SUPABASE_CDN
];

async function cacheOne(cache, url){
    try{
        const response = await fetch(url, {cache:"reload"});
        if(response.ok || response.type === "opaque"){
            await cache.put(url, response.clone());
        }
    }catch(error){
        // Instalasi tetap valid jika satu resource eksternal sedang tidak tersedia.
    }
}

self.addEventListener("install", event => {
    event.waitUntil((async () => {
        const cache = await caches.open(CACHE_VERSION);
        await Promise.allSettled(APP_SHELL.map(url => cacheOne(cache, url)));
        await self.skipWaiting();
    })());
});

self.addEventListener("activate", event => {
    event.waitUntil((async () => {
        const keys = await caches.keys();
        await Promise.all(keys
            .filter(key => key.startsWith("ldm-stage16-") && ![CACHE_VERSION,RUNTIME_CACHE].includes(key))
            .map(key => caches.delete(key))
        );
        await self.clients.claim();
    })());
});

async function cacheFirst(request){
    const cached = await caches.match(request, {ignoreSearch:true});
    if(cached){
        return cached;
    }
    const response = await fetch(request);
    if(response.ok || response.type === "opaque"){
        const cache = await caches.open(RUNTIME_CACHE);
        await cache.put(request, response.clone());
    }
    return response;
}

async function networkFirstNavigation(request){
    try{
        const response = await fetch(request);
        if(response.ok){
            const cache = await caches.open(RUNTIME_CACHE);
            await cache.put(request, response.clone());
        }
        return response;
    }catch(error){
        const exact = await caches.match(request, {ignoreSearch:true});
        if(exact){
            return exact;
        }
        const requestedUrl = new URL(request.url);
        if(requestedUrl.pathname.toLowerCase().endsWith("/kasir.html")){
            const cashier = await caches.match("./kasir.html", {ignoreSearch:true});
            if(cashier){
                return cashier;
            }
        }
        return new Response(
            "Halaman ini belum tersedia offline. Sambungkan internet lalu coba lagi.",
            {status:503,headers:{"Content-Type":"text/plain; charset=utf-8"}}
        );
    }
}

self.addEventListener("fetch", event => {
    const request = event.request;
    const url = new URL(request.url);

    if(request.method !== "GET"){
        return;
    }

    // Permintaan REST/Auth Supabase tidak pernah dicache.
    if(/\.supabase\.co$/i.test(url.hostname)){
        return;
    }

    if(request.mode === "navigate"){
        event.respondWith(networkFirstNavigation(request));
        return;
    }

    if(url.origin === self.location.origin || url.hostname === "cdn.jsdelivr.net"){
        event.respondWith(cacheFirst(request));
    }
});

self.addEventListener("sync", event => {
    if(event.tag !== "ldm-offline-sales-v16"){
        return;
    }
    event.waitUntil((async () => {
        const clients = await self.clients.matchAll({type:"window",includeUncontrolled:true});
        clients.forEach(client => client.postMessage({type:"LDM_SYNC_REQUEST"}));
    })());
});

self.addEventListener("message", event => {
    if(event.data && event.data.type === "LDM_SKIP_WAITING"){
        self.skipWaiting();
    }
});
