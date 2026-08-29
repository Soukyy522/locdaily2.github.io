(function(){
    "use strict";

    const TOKEN_KEY="ldmLicenseActivationTokenV23";
    const CERT_KEY="ldmLicenseCertificateV23";
    const INSTALLATION_KEY="ldmLicenseInstallationIdV23";
    const STORE_REF_KEY="ldmLicenseStoreRefV23";
    const config=window.LDM_LICENSE_CONFIG||{};
    let currentPayload=null;
    let currentMode="unlicensed";

    const PAGE_FEATURES={
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
        "device-management.html":"cloud_devices",
        "device-access.html":"cloud_devices",
        "cloud-control-center.html":"cloud_devices"
    };

    function normalizedPage(value){
        let page=String(value||"").split("#")[0].split("?")[0];
        try{page=decodeURIComponent(page)}catch(error){}
        return page.replace(/^.*\//,"").toLowerCase();
    }

    function installationId(){
        let id=localStorage.getItem(INSTALLATION_KEY)||"";
        if(!id){
            id=(crypto.randomUUID&&crypto.randomUUID())||(
                Date.now().toString(36)+"-"+Array.from(crypto.getRandomValues(new Uint8Array(16)))
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
        if(!config.publicSigningJwk){
            throw new Error("LICENSE_PUBLIC_KEY_NOT_CONFIGURED");
        }
        const key=await crypto.subtle.importKey(
            "jwk",
            config.publicSigningJwk,
            {name:"ECDSA",namedCurve:"P-256"},
            false,
            ["verify"]
        );
        const valid=await crypto.subtle.verify(
            {name:"ECDSA",hash:"SHA-256"},
            key,
            base64UrlBytes(certificate.signature),
            new TextEncoder().encode(certificate.payload)
        );
        if(!valid)throw new Error("LICENSE_SIGNATURE_INVALID");
        const payload=JSON.parse(certificate.payload);
        if(payload.version!==1||payload.issuer!=="LocDailyMar License Authority"){
            throw new Error("LICENSE_CERTIFICATE_INVALID");
        }
        if(payload.isLifetime!==true&&!payload.licenseExpiresAt){
            throw new Error("LICENSE_CERTIFICATE_INVALID");
        }
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

    function clearLicense(){
        localStorage.removeItem(TOKEN_KEY);
        localStorage.removeItem(CERT_KEY);
        currentPayload=null;
        currentMode="unlicensed";
    }

    function shouldClearForError(error){
        return [
            "LICENSE_ACTIVATION_REQUIRED","ACTIVATION_NOT_FOUND",
            "LICENSE_SIGNATURE_INVALID","LICENSE_CERTIFICATE_INVALID"
        ].includes(String(error&&error.message||""));
    }

    async function request(body){
        if(!/^https:\/\//i.test(String(config.serverUrl||""))||/PROJECT-REF-LISENSI/i.test(config.serverUrl)){
            throw new Error("LICENSE_SERVER_URL_NOT_CONFIGURED");
        }
        let response;
        try{
            response=await fetch(config.serverUrl,{
                method:"POST",
                headers:{"Content-Type":"application/json"},
                body:JSON.stringify(body),
                cache:"no-store",
                referrerPolicy:"strict-origin-when-cross-origin"
            });
        }catch(error){
            const networkError=new Error("LICENSE_NETWORK_ERROR");
            networkError.cause=error;
            throw networkError;
        }
        const data=await response.json().catch(()=>({}));
        if(!response.ok){
            const error=new Error(String(data.error||`LICENSE_HTTP_${response.status}`));
            error.serverResponse=true;
            error.status=response.status;
            throw error;
        }
        return data;
    }

    async function activate({licenseKey,storeRef,deviceName}){
        const cleanStore=String(storeRef||"").trim();
        const data=await request({
            action:"activate",
            licenseKey:String(licenseKey||"").trim(),
            installationId:installationId(),
            storeRef:cleanStore,
            deviceName:String(deviceName||navigator.userAgentData?.platform||"Perangkat LocDailyMar"),
            platform:String(navigator.userAgentData?.platform||navigator.platform||"browser"),
            appVersion:String(config.appVersion||"unknown")
        });
        const payload=await verifyCertificate(data.certificate);
        saveLicense(data.activationToken,data.certificate,cleanStore);
        currentPayload=payload;
        currentMode="online";
        return payload;
    }

    async function startTrial({customerName,customerEmail,whatsapp,storeRef,deviceName,trialConsent}){
        const cleanStore=String(storeRef||"").trim();
        const data=await request({
            action:"start_trial",
            customerName:String(customerName||"").trim(),
            customerEmail:String(customerEmail||"").trim().toLowerCase(),
            whatsapp:String(whatsapp||"").trim(),
            trialConsent:trialConsent===true,
            installationId:installationId(),
            storeRef:cleanStore,
            deviceName:String(deviceName||navigator.userAgentData?.platform||"Perangkat Trial LocDailyMar"),
            platform:String(navigator.userAgentData?.platform||navigator.platform||"browser"),
            appVersion:String(config.appVersion||"unknown")
        });
        const payload=await verifyCertificate(data.certificate);
        if(payload.isTrial!==true)throw new Error("TRIAL_CERTIFICATE_INVALID");
        saveLicense(data.activationToken,data.certificate,cleanStore);
        currentPayload=payload;
        currentMode="trial-online";
        return payload;
    }

    async function validateOnline(){
        const activationToken=localStorage.getItem(TOKEN_KEY)||"";
        if(!activationToken)throw new Error("LICENSE_ACTIVATION_REQUIRED");
        const data=await request({
            action:"validate",
            activationToken,
            installationId:installationId(),
            appVersion:String(config.appVersion||"unknown")
        });
        const payload=await verifyCertificate(data.certificate);
        saveLicense("",data.certificate,String(payload.storeRef||""));
        currentPayload=payload;
        currentMode="online";
        return payload;
    }

    async function ensureValid(){
        const certificate=readCertificate();
        if(!certificate||!localStorage.getItem(TOKEN_KEY))throw new Error("LICENSE_ACTIVATION_REQUIRED");
        const cached=await verifyCertificate(certificate);
        const now=Date.now();
        if(cached.isLifetime!==true&&now>=Date.parse(cached.licenseExpiresAt)){
            if(navigator.onLine!==false){
                try{return await validateOnline()}
                catch(error){throw error}
            }
            throw new Error("LICENSE_EXPIRED");
        }
        if(navigator.onLine!==false&&now>=Date.parse(cached.onlineCheckAfter)){
            try{return await validateOnline()}
            catch(error){
                if(error.serverResponse){
                    if(shouldClearForError(error))clearLicense();
                    throw error;
                }
                if(now>=Date.parse(cached.offlineGraceUntil))throw new Error("LICENSE_OFFLINE_GRACE_EXPIRED");
                currentPayload=cached;
                currentMode="offline-grace";
                return cached;
            }
        }
        if(navigator.onLine===false&&now>=Date.parse(cached.offlineGraceUntil)){
            throw new Error("LICENSE_OFFLINE_GRACE_EXPIRED");
        }
        currentPayload=cached;
        currentMode=navigator.onLine===false?"offline-grace":"cached";
        return cached;
    }

    async function deactivate(){
        const activationToken=localStorage.getItem(TOKEN_KEY)||"";
        if(activationToken&&navigator.onLine!==false){
            await request({action:"deactivate",activationToken,installationId:installationId()});
        }
        clearLicense();
        return true;
    }

    function hasFeature(feature){
        if(!config.enabled)return true;
        return Boolean(currentPayload&&Array.isArray(currentPayload.features)&&currentPayload.features.includes(feature));
    }

    function featureForPage(page){return PAGE_FEATURES[normalizedPage(page)]||""}

    function applyFeatureVisibility(root){
        if(!config.enabled||!currentPayload)return;
        (root||document).querySelectorAll("a[href]").forEach(anchor=>{
            const feature=featureForPage(anchor.getAttribute("href"));
            if(feature&&!hasFeature(feature)){
                anchor.hidden=true;
                anchor.setAttribute("aria-hidden","true");
                anchor.dataset.ldmLicenseHidden="true";
            }
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
                location.href="dashboard.html?licenseFeatureBlocked="+encodeURIComponent(feature);
            }
        },true);
        if(document.readyState==="loading"){
            document.addEventListener("DOMContentLoaded",()=>applyFeatureVisibility(document),{once:true});
        }
    }

    function status(){
        return {enabled:Boolean(config.enabled),mode:currentMode,payload:currentPayload};
    }

    function activationUrl(errorCode){
        const returnTo=normalizedPage(location.pathname)||"dashboard.html";
        const query=new URLSearchParams({returnTo});
        if(errorCode)query.set("error",errorCode);
        return `license.html?${query.toString()}`;
    }

    async function bootGuard(){
        if(!config.enabled){
            document.documentElement.classList.remove("ldm-license-pending");
            window.dispatchEvent(new CustomEvent("ldm-license-ready",{detail:status()}));
            return;
        }
        try{
            await ensureValid();
            const required=featureForPage(location.pathname);
            if(required&&!hasFeature(required)){
                location.replace("dashboard.html?licenseFeatureBlocked="+encodeURIComponent(required));
                return;
            }
            bindFeatureGate();
            applyFeatureVisibility(document);
            document.documentElement.classList.remove("ldm-license-pending");
            window.dispatchEvent(new CustomEvent("ldm-license-ready",{detail:status()}));
        }catch(error){
            if(shouldClearForError(error))clearLicense();
            location.replace(activationUrl(error.message||"LICENSE_INVALID"));
        }
    }

    window.LDMLicense=Object.freeze({
        activate,startTrial,validateOnline,ensureValid,deactivate,hasFeature,featureForPage,
        applyFeatureVisibility,status,installationId,readCertificate,bootGuard
    });
})();
