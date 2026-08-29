(function(){
"use strict";

const EXEMPT=new Set([
    "index.html",
    "license.html",
    "payment-gateway.html",
    "developer-license.html",
    "account-password-reset.html",
    "404.html"
]);

const PAGE_FEATURE=Object.freeze({
    "dashboard.html":"core_pos",
    "barang.html":"core_pos",
    "kasir.html":"core_pos",
    "laporan.html":"core_pos",
    "absensi.html":"core_pos",
    "kartu-stok.html":"core_pos",

    "account-management.html":"account_device",
    "device-management.html":"account_device",
    "device-access.html":"account_device",

    "retur.html":"returns",
    "stock-opname.html":"stock_opname",
    "pengeluaran.html":"expenses",
    "backup & restore.html":"backup_restore",
    "supplier.html":"supplier",
    "multi-store.html":"multi_store",

    "purchase-order.html":"procurement",
    "goods.receipt.html":"procurement",
    "shift-closing.html":"closing_eod",
    "eod.html":"closing_eod",
    "recovery-center.html":"recovery",
    "pwa-settings.html":"pwa_offline",
    "offline.html":"pwa_offline",
    "cloud-control-center.html":"cloud_control"
});

function page(){
    return decodeURIComponent(location.pathname.split("/").pop()||"index.html").toLowerCase();
}

function isDeveloperTool(name){
    return name.startsWith("supabase-")
        || name==="qa-security-performance.html"
        || name==="pages-health-check.html";
}

function gate(){
    let el=document.getElementById("ldmLicenseChecking");
    if(el)return el;
    el=document.createElement("div");
    el.id="ldmLicenseChecking";
    el.style.cssText="position:fixed;inset:0;z-index:2147483646;background:#f4f7fb;display:grid;place-items:center;font:700 14px Arial;color:#172033";
    el.innerHTML='<div style="max-width:360px;text-align:center;padding:22px;background:white;border:1px solid #e4e7ec;border-radius:16px;box-shadow:0 12px 32px rgba(16,24,40,.08)">🔐 Memeriksa lisensi LocDailyMar...</div>';
    document.documentElement.appendChild(el);
    return el;
}

function redirectLicense(reason,feature=""){
    const q=new URLSearchParams();
    q.set("reason",reason||"inactive");
    if(feature)q.set("feature",feature);
    location.replace("license.html?"+q.toString());
}

async function run(){
    const current=page();
    if(EXEMPT.has(current))return;

    gate();

    try{
        if(!window.LDMSupabase?.createClient){
            redirectLicense("license_runtime_missing");
            return;
        }

        const supabase=window.LDMSupabase.createClient();
        const {data,error}=await supabase.auth.getSession();
        if(error)throw error;

        if(!data?.session){
            location.replace("index.html?reason=auth_required");
            return;
        }

        if(!window.LDMLicense){
            redirectLicense("license_service_missing");
            return;
        }

        const ctx=await window.LDMLicense.context();
        window.LDM_LICENSE_CONTEXT=ctx;

        if(ctx.valid!==true){
            redirectLicense(ctx.status||"inactive");
            return;
        }

        if(isDeveloperTool(current) && !ctx.developer_admin){
            redirectLicense("developer_tool_locked","developer_tools");
            return;
        }

        const required=PAGE_FEATURE[current]||null;
        if(required && !window.LDMLicense.hasFeature(ctx,required)){
            redirectLicense("feature_locked",required);
            return;
        }

        document.getElementById("ldmLicenseChecking")?.remove();
        window.dispatchEvent(new CustomEvent("ldm-license-ready",{detail:ctx}));

    }catch(error){
        console.error("License Guard fail-closed:",error);
        redirectLicense("license_check_error");
    }
}

if(document.readyState==="loading"){
    document.addEventListener("DOMContentLoaded",run,{once:true});
}else{
    run();
}
})();
