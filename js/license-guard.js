(function(){
"use strict";
const EXEMPT=new Set(["license.html","payment-gateway.html","developer-license.html","index.html","offline.html"]);
function page(){return (location.pathname.split("/").pop()||"index.html").toLowerCase()}
function showGate(){let el=document.getElementById("ldmLicenseChecking");if(el)return el;el=document.createElement("div");el.id="ldmLicenseChecking";el.style.cssText="position:fixed;inset:0;z-index:2147483646;background:#f4f7fb;display:grid;place-items:center;font:700 14px Arial;color:#172033";el.innerHTML='<div style="padding:22px;background:white;border:1px solid #e4e7ec;border-radius:16px">🔐 Memeriksa lisensi LocDailyMar...</div>';document.documentElement.appendChild(el);return el}
function hideGate(){document.getElementById("ldmLicenseChecking")?.remove()}
async function run(){if(EXEMPT.has(page()))return;try{const supabase=window.LDMSupabase?.createClient?.();if(!supabase)return;const {data}=await supabase.auth.getSession();if(!data?.session)return;showGate();if(!window.LDMLicense)throw new Error("license-service.js belum termuat.");const ctx=await window.LDMLicense.context();window.LDM_LICENSE_CONTEXT=ctx;if(ctx.valid===true){hideGate();window.dispatchEvent(new CustomEvent("ldm-license-ready",{detail:ctx}));return}const target="license.html?reason="+encodeURIComponent(ctx.status||"inactive");location.replace(target)}catch(error){console.warn("License Guard fail-open:",error);hideGate();window.dispatchEvent(new CustomEvent("ldm-license-check-error",{detail:{message:error?.message||String(error)}}))}}
if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",run,{once:true});else run();
})();
