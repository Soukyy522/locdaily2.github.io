(function(){
    "use strict";

    const VERSION="23.1.0";
    const TOKEN_KEY="ldmLicenseActivationTokenV231";
    const CERT_KEY="ldmLicenseCertificateV231";
    const INSTALLATION_KEY="ldmLicenseInstallationIdV231";
    const STORE_REF_KEY="ldmLicenseStoreRefV231";
    const config=window.LDM_LICENSE_CONFIG||{};
    let currentPayload=null;
    let currentMode="unlicensed";

    const PAGE_FEATURES=Object.freeze({
        "index.html":"dashboard",
        "dashboard.html":"dashboard",
        "absensi.html":"attendance",
        "kasir.html":"pos",
        "barang.html":"inventory",
        "kartu-stok.html":"stock_card",
        "stock-opname.html":"stock_opname",
        "multi-store.html":"multi_store",
        "supplier.html":"suppliers",
        "purchase-order.html":"purchase_order",
        "goods.receipt.html":"goods_receipt",
        "retur.html":"returns",
        "laporan.html":"reports",
        "pengeluaran.html":"expenses",
        "shift-closing.html":"shift_closing",
        "eod.html":"eod",
        "backup & restore.html":"backup_restore",
        "pwa-settings.html":"app_update",
        "recovery-center.html":"recovery_center",
        "qa-security-performance.html":"qa_security",
        "account-management.html":"cloud_accounts",
        "account-password-reset.html":"cloud_accounts",
        "device-management.html":"cloud_devices",
        "device-access.html":"cloud_devices",
        "cloud-control-center.html":"cloud_control",
        "pages-health-check.html":"qa_security",
        "supabase-connection-test.html":"qa_security",
        "supabase-stage4-test.html":"qa_security",
        "supabase-stage5-auth-test.html":"qa_security",
        "supabase-stage6-auth-authority-test.html":"qa_security",
        "supabase-stage7-products-migration.html":"qa_security",
        "supabase-stage7-realtime-test.html":"qa_security",
        "supabase-stage8-transactions-stock-test.html":"qa_security",
        "supabase-stage9-attendance-migration.html":"qa_security",
        "supabase-stage9-attendance-test.html":"qa_security",
        "supabase-stage10-inventory-migration.html":"qa_security",
        "supabase-stage10-inventory-test.html":"qa_security",
        "supabase-stage11-procurement-migration.html":"qa_security",
        "supabase-stage11-procurement-test.html":"qa_security",
        "supabase-stage12-reporting-migration.html":"qa_security",
        "supabase-stage12-reporting-test.html":"qa_security",
        "supabase-stage14-account-test.html":"qa_security",
        "supabase-stage16-offline-queue-test.html":"qa_security",
        "supabase-stage17-recovery-test.html":"qa_security",
        "supabase-stage19.1.2-cost-history-test.html":"qa_security",
        "supabase-stage20-unit-test.html":"qa_security"
    });

    const PUBLIC_PAGES=new Set(["license.html","offline.html","404.html"]);

    function normalizedPage(value){
        let page=String(value||"").split("#")[0].split("?")[0];
        try{page=decodeURIComponent(page)}catch(error){}
        return page.replace(/^.*\//,"").toLowerCase()||"index.html";
    }

    function configurationStatus(){
        const url=String(config.serverUrl||"");
        const whatsapp=String(config.developerWhatsapp||"").replace(/\D/g,"");
        return {
            enabled:config.enabled===true,
            secureContext:Boolean(window.isSecureContext||location.hostname==="localhost"),
            serverUrlReady:/^https:\/\/[a-z0-9-]+\.supabase\.co\/functions\/v1\/ldm-license$/i.test(url)&&!/PROJECT-REF/i.test(url),
            publicKeyReady:Boolean(config.publicSigningJwk&&config.publicSigningJwk.kty==="EC"&&config.publicSigningJwk.crv==="P-256"&&config.publicSigningJwk.x&&config.publicSigningJwk.y),
            whatsappReady:/^62\d{8,15}$/.test(whatsapp)&&!/X/i.test(String(config.developerWhatsapp||"")),
            serverUrl:url,
            appVersion:String(config.appVersion||VERSION)
        };
    }

    function installationId(){
        let id=localStorage.getItem(INSTALLATION_KEY)||"";
        if(!id){
            id=(crypto.randomUUID&&crypto.randomUUID())||(
                Date.now().toString(36)+"-"+Array.from(crypto.getRandomValues(new Uint8Array(18)))
                    .map(value=>value.toString(16).padStart(2,"0")).join("")
            );
            localStorage.setItem(INSTALLATION_KEY,id);
        }
        return id;
    }

    function base64UrlBytes(value){
        const input=String(value||"").replace(/-/g,"+").replace(/_/g,"/");
        const padded=input+"=".repeat((4-input.length%4)%4);
        const binary=atob(padded);
        return Uint8Array.from(binary,char=>char.charCodeAt(0));
    }

    async function verifyCertificate(certificate){
        if(!certificate||typeof certificate.payload!=="string"||!certificate.signature){
            throw new Error("LICENSE_CERTIFICATE_INVALID");
        }
        const setup=configurationStatus();
        if(!setup.publicKeyReady)throw new Error("LICENSE_PUBLIC_KEY_NOT_CONFIGURED");
        let key;
        try{
            key=await crypto.subtle.importKey("jwk",config.publicSigningJwk,{name:"ECDSA",namedCurve:"P-256"},false,["verify"]);
        }catch(error){throw new Error("LICENSE_PUBLIC_KEY_INVALID")}
        const valid=await crypto.subtle.verify(
            {name:"ECDSA",hash:"SHA-256"},key,base64UrlBytes(certificate.signature),
            new TextEncoder().encode(certificate.payload)
        );
        if(!valid)throw new Error("LICENSE_SIGNATURE_INVALID");
        let payload;
        try{payload=JSON.parse(certificate.payload)}catch(error){throw new Error("LICENSE_CERTIFICATE_INVALID")}
        if(payload.version!==2||payload.issuer!=="LocDailyMar License Authority"||!Array.isArray(payload.features)){
            throw new Error("LICENSE_CERTIFICATE_INVALID");
        }
        if(payload.installationId!==installationId())throw new Error("LICENSE_DEVICE_MISMATCH");
        if(payload.isLifetime!==true&&!payload.licenseExpiresAt)throw new Error("LICENSE_CERTIFICATE_INVALID");
        return payload;
    }

    function readCertificate(){
        try{return JSON.parse(localStorage.getItem(CERT_KEY)||"null")}
        catch(error){return null}
    }

    function saveLicense(activationToken,certificate,storeRef){
        if(activationToken)localStorage.setItem(TOKEN_KEY,activationToken);
        localStorage.setItem(CERT_KEY,JSON.stringify(certificate));
        if(storeRef)localStorage.setItem(STORE_REF_KEY,storeRef);
    }

    function clearLicense(options){
        localStorage.removeItem(TOKEN_KEY);
        localStorage.removeItem(CERT_KEY);
        if(options&&options.removeStore)localStorage.removeItem(STORE_REF_KEY);
        currentPayload=null;
        currentMode="unlicensed";
    }

    function shouldClearForError(error){
        return ["ACTIVATION_NOT_FOUND","LICENSE_SIGNATURE_INVALID","LICENSE_CERTIFICATE_INVALID","LICENSE_DEVICE_MISMATCH"].includes(String(error&&error.message||""));
    }

    async function request(body){
        const setup=configurationStatus();
        if(!setup.serverUrlReady)throw new Error("LICENSE_SERVER_URL_NOT_CONFIGURED");
        if(!setup.secureContext)throw new Error("LICENSE_HTTPS_REQUIRED");
        let response;
        try{
            response=await fetch(config.serverUrl,{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(body),cache:"no-store",referrerPolicy:"strict-origin-when-cross-origin"});
        }catch(cause){
            const error=new Error("LICENSE_NETWORK_ERROR");
            error.cause=cause;
            throw error;
        }
        const data=await response.json().catch(()=>({}));
        if(!response.ok){
            const error=new Error(String(data.error||`LICENSE_HTTP_${response.status}`));
            error.status=response.status;
            error.requestId=data.requestId||"";
            error.detail=data.detail||"";
            error.serverResponse=true;
            throw error;
        }
        return data;
    }

    function deviceName(){return String(navigator.userAgentData?.platform||navigator.platform||"Browser LocDailyMar")}

    async function activate({licenseKey,storeRef,deviceLabel}){
        const cleanStore=String(storeRef||"").trim().toUpperCase();
        const data=await request({action:"activate",licenseKey:String(licenseKey||"").trim(),installationId:installationId(),storeRef:cleanStore,deviceName:String(deviceLabel||deviceName()),platform:deviceName(),appVersion:String(config.appVersion||VERSION)});
        const payload=await verifyCertificate(data.certificate);
        saveLicense(data.activationToken,data.certificate,cleanStore);
        currentPayload=payload; currentMode="online";
        return payload;
    }

    async function startTrial({customerName,customerEmail,whatsapp,storeRef,deviceLabel,trialConsent}){
        const cleanStore=String(storeRef||"").trim().toUpperCase();
        const data=await request({action:"start_trial",customerName:String(customerName||"").trim(),customerEmail:String(customerEmail||"").trim().toLowerCase(),whatsapp:String(whatsapp||"").trim(),trialConsent:trialConsent===true,installationId:installationId(),storeRef:cleanStore,deviceName:String(deviceLabel||deviceName()),platform:deviceName(),appVersion:String(config.appVersion||VERSION)});
        const payload=await verifyCertificate(data.certificate);
        if(payload.isTrial!==true)throw new Error("TRIAL_CERTIFICATE_INVALID");
        saveLicense(data.activationToken,data.certificate,cleanStore);
        currentPayload=payload; currentMode="trial-online";
        return payload;
    }

    async function validateOnline(){
        const activationToken=localStorage.getItem(TOKEN_KEY)||"";
        if(!activationToken)throw new Error("LICENSE_ACTIVATION_REQUIRED");
        const data=await request({action:"validate",activationToken,installationId:installationId(),storeRef:localStorage.getItem(STORE_REF_KEY)||"",appVersion:String(config.appVersion||VERSION)});
        const payload=await verifyCertificate(data.certificate);
        saveLicense("",data.certificate,String(payload.storeRef||""));
        currentPayload=payload; currentMode="online";
        return payload;
    }

    function timestamp(value){const time=Date.parse(String(value||"")); return Number.isFinite(time)?time:0}

    async function ensureValid(){
        const certificate=readCertificate();
        if(!certificate||!localStorage.getItem(TOKEN_KEY))throw new Error("LICENSE_ACTIVATION_REQUIRED");
        const cached=await verifyCertificate(certificate);
        const now=Date.now();
        if(cached.isLifetime!==true&&now>=timestamp(cached.licenseExpiresAt))throw new Error("LICENSE_EXPIRED");
        if(now>=timestamp(cached.offlineGraceUntil)&&navigator.onLine===false)throw new Error("LICENSE_OFFLINE_GRACE_EXPIRED");
        if(navigator.onLine!==false&&now>=timestamp(cached.onlineCheckAfter)){
            try{return await validateOnline()}
            catch(error){
                if(error.serverResponse){if(shouldClearForError(error))clearLicense(); throw error}
                if(now>=timestamp(cached.offlineGraceUntil))throw new Error("LICENSE_OFFLINE_GRACE_EXPIRED");
                currentPayload=cached; currentMode="offline-grace"; return cached;
            }
        }
        currentPayload=cached;
        currentMode=navigator.onLine===false?"offline-grace":"cached";
        return cached;
    }

    async function deactivate(){
        const activationToken=localStorage.getItem(TOKEN_KEY)||"";
        if(activationToken&&navigator.onLine!==false){await request({action:"deactivate",activationToken,installationId:installationId()})}
        clearLicense({removeStore:true});
        return true;
    }

    function hasFeature(feature){
        if(config.enabled!==true)return true;
        return Boolean(currentPayload&&Array.isArray(currentPayload.features)&&currentPayload.features.includes(feature));
    }
    function featureForPage(page){return PAGE_FEATURES[normalizedPage(page)]||""}

    function applyFeatureVisibility(root){
        if(config.enabled!==true||!currentPayload)return;
        (root||document).querySelectorAll("a[href]").forEach(anchor=>{
            const feature=featureForPage(anchor.getAttribute("href"));
            const blocked=Boolean(feature&&!hasFeature(feature));
            anchor.hidden=blocked;
            anchor.toggleAttribute("aria-hidden",blocked);
            if(blocked)anchor.dataset.ldmLicenseHidden="true"; else delete anchor.dataset.ldmLicenseHidden;
        });
    }

    function bindFeatureGate(){
        if(document.documentElement.dataset.ldmLicenseGateBound==="true")return;
        document.documentElement.dataset.ldmLicenseGateBound="true";
        document.addEventListener("click",event=>{
            const anchor=event.target&&event.target.closest&&event.target.closest("a[href]");
            if(!anchor)return;
            const feature=featureForPage(anchor.getAttribute("href"));
            if(feature&&!hasFeature(feature)){
                event.preventDefault();
                location.href=`license.html?error=FEATURE_LOCKED&feature=${encodeURIComponent(feature)}`;
            }
        },true);
    }

    function status(){return {enabled:config.enabled===true,mode:currentMode,payload:currentPayload,configuration:configurationStatus()}}

    function activationUrl(errorCode){
        const returnTo=normalizedPage(location.pathname)||"dashboard.html";
        const query=new URLSearchParams({returnTo});
        if(errorCode)query.set("error",String(errorCode));
        return `license.html?${query.toString()}`;
    }

    async function bootGuard(){
        const page=normalizedPage(location.pathname);
        if(PUBLIC_PAGES.has(page)||config.enabled!==true){
            document.documentElement.classList.remove("ldm-license-pending");
            window.dispatchEvent(new CustomEvent("ldm-license-ready",{detail:status()}));
            return true;
        }
        document.documentElement.classList.add("ldm-license-pending");
        try{
            await ensureValid();
            const required=featureForPage(page);
            if(required&&!hasFeature(required)){
                location.replace(`license.html?error=FEATURE_LOCKED&feature=${encodeURIComponent(required)}`); return false;
            }
            bindFeatureGate(); applyFeatureVisibility(document);
            document.documentElement.classList.remove("ldm-license-pending");
            window.dispatchEvent(new CustomEvent("ldm-license-ready",{detail:status()}));
            return true;
        }catch(error){
            if(shouldClearForError(error))clearLicense();
            location.replace(activationUrl(error.message||"LICENSE_INVALID"));
            return false;
        }
    }

    window.LDMLicense=Object.freeze({version:VERSION,activate,startTrial,validateOnline,ensureValid,deactivate,clearLicense,hasFeature,featureForPage,applyFeatureVisibility,status,configurationStatus,installationId,readCertificate,bootGuard});
})();
