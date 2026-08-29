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
    if(window.LDM_LICENSE_CONFIG.enabled && !["license.html","offline.html","404.html"].includes(page)){
        document.documentElement.classList.add("ldm-license-pending");
        const style=document.createElement("style");
        style.id="ldmLicensePendingStyle";
        style.textContent="html.ldm-license-pending body{visibility:hidden!important}";
        document.head.appendChild(style);
    }
})();
