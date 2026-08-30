(function(){
    "use strict";

    /*
     * TAHAP 23.1 - konfigurasi publik lisensi.
     * 1. Ganti PROJECT-REF-LISENSI.
     * 2. Tempel PUBLIC JWK dari tools/generate-license-signing-key.mjs.
     * 3. Ganti developerWhatsapp dengan format 628xxxxxxxxxx.
     * Private JWK dan DEVICE PEPPER TIDAK BOLEH dimasukkan ke file ini.
     */
    window.LDM_LICENSE_CONFIG=Object.freeze({
        enabled:true,
        serverUrl:"https://pbrluziihlcqtjesakmg.supabase.co/functions/v1/ldm-license",
        appVersion:"23.1.0",
        publicSigningJwk:{
  "key_ops": [
    "verify"
  ],
  "ext": true,
  "kty": "EC",
  "x": "0dgzgUy_PFPOlqHRTHyBNh2Doe8uLlUf20Gv6LX_r7w",
  "y": "ehdfHZNq0WneSoE1YoZslm2GnnOdSlO9mZYEBFXsPWY",
  "crv": "P-256"
},
        developerWhatsapp:"6283117590286",
        supportName:"Developer LocDailyMar",
        validationIntervalMinutes:60,
        plans:Object.freeze({
            WARUNG_KECIL:Object.freeze({name:"Warung Kecil",monthly:29000,yearly:299000,maxDevices:1,maxStores:1}),
            WARUNG_SEDERHANA:Object.freeze({name:"Warung Sederhana",monthly:59000,yearly:599000,maxDevices:3,maxStores:1,trialDays:14}),
            TOKO:Object.freeze({name:"Toko",monthly:99000,yearly:999000,maxDevices:10,maxStores:5}),
            LIFETIME:Object.freeze({name:"Lifetime",once:3499000,maxDevices:15,maxStores:8})
        })
    });

    const page=(location.pathname.split("/").pop()||"index.html").toLowerCase();
    const publicPage=["license.html","offline.html","404.html"].includes(page);
    let watchdog=0;

    function returnTarget(){
        return /^[A-Za-z0-9._% -]+\.html$/i.test(page)?page:"dashboard.html";
    }

    function mountGateScreen(){
        if(publicPage||!window.LDM_LICENSE_CONFIG.enabled)return;
        document.documentElement.classList.add("ldm-license-pending");
        if(!document.getElementById("ldmLicensePendingStyle")){
            const style=document.createElement("style");
            style.id="ldmLicensePendingStyle";
            style.textContent=`
                html.ldm-license-pending body{overflow:hidden!important}
                html.ldm-license-pending body>*:not(#ldmLicenseGateScreen){visibility:hidden!important}
                #ldmLicenseGateScreen{display:none;visibility:visible!important;position:fixed;inset:0;z-index:2147483647;place-items:center;padding:24px;background:linear-gradient(135deg,#0d2240,#07182d);font-family:Inter,Poppins,Arial,sans-serif;color:#fff}
                html.ldm-license-pending #ldmLicenseGateScreen{display:grid}
                #ldmLicenseGateScreen .ldm-gate-card{width:min(390px,100%);text-align:center;padding:28px 22px;border:1px solid rgba(255,255,255,.16);border-radius:20px;background:rgba(255,255,255,.08);box-shadow:0 18px 50px rgba(0,0,0,.25)}
                #ldmLicenseGateScreen .ldm-gate-spinner{width:42px;height:42px;margin:0 auto 15px;border:4px solid rgba(255,255,255,.22);border-top-color:#ffc107;border-radius:50%;animation:ldmGateSpin .8s linear infinite}
                #ldmLicenseGateScreen strong{display:block;font-size:1rem;margin-bottom:6px}
                #ldmLicenseGateScreen span{display:block;color:#c7d5e5;font-size:.76rem;line-height:1.55}
                @keyframes ldmGateSpin{to{transform:rotate(360deg)}}
            `;
            document.head.appendChild(style);
        }
        if(!document.body||document.getElementById("ldmLicenseGateScreen"))return;
        const screen=document.createElement("div");
        screen.id="ldmLicenseGateScreen";
        screen.setAttribute("role","status");
        screen.setAttribute("aria-live","polite");
        screen.innerHTML='<div class="ldm-gate-card"><div class="ldm-gate-spinner" aria-hidden="true"></div><strong>Memeriksa lisensi aplikasi</strong><span>Mohon tunggu. Aplikasi sedang memastikan paket, perangkat, dan Store Code.</span></div>';
        document.body.appendChild(screen);
    }

    function completeGate(){
        clearTimeout(watchdog);
        document.documentElement.classList.remove("ldm-license-pending");
        document.getElementById("ldmLicenseGateScreen")?.remove();
    }

    function failGate(code){
        clearTimeout(watchdog);
        if(publicPage)return;
        const query=new URLSearchParams({returnTo:returnTarget(),error:String(code||"LICENSE_GUARD_TIMEOUT")});
        location.replace(`license.html?${query.toString()}`);
    }

    window.LDMLicenseGate=Object.freeze({mount:mountGateScreen,complete:completeGate,fail:failGate});

    if(window.LDM_LICENSE_CONFIG.enabled&&!publicPage){
        if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",mountGateScreen,{once:true});
        else mountGateScreen();

        /* Cadangan bila security-hardening.js versi lama masih berada di cache. */
        window.addEventListener("load",()=>{
            if(!document.documentElement.classList.contains("ldm-license-pending"))return;
            if(window.LDMLicense&&typeof window.LDMLicense.bootGuard==="function"){
                window.LDMLicense.bootGuard().catch(()=>undefined);
            }
        },{once:true});

        /* Jangan pernah membiarkan pengguna melihat halaman putih tanpa akhir. */
        watchdog=window.setTimeout(()=>{
            if(document.documentElement.classList.contains("ldm-license-pending"))failGate("LICENSE_GUARD_TIMEOUT");
        },12000);
    }
})();
