(function(){
"use strict";
let realtimeChannel=null;
function client(){if(!window.LDMSupabase)throw new Error("Supabase client belum tersedia.");return window.LDMSupabase.createClient()}
function role(){return String(localStorage.getItem("userRole")||localStorage.getItem("role")||"").trim().toLowerCase()}
async function plans(){const {data,error}=await client().rpc("ldm_license_plans");if(error)throw error;return Array.isArray(data)?data:[]}
async function context(){const {data,error}=await client().rpc("ldm_license_context");if(error)throw error;return data||{valid:false,status:"none"}}
async function startTrial(){if(role()!=="owner")throw new Error("Hanya Owner yang dapat memulai trial.");const {data,error}=await client().rpc("ldm_start_sederhana_trial");if(error)throw error;return data}
async function history(){if(role()!=="owner")return[];const {data,error}=await client().rpc("ldm_license_payment_history");if(error)throw error;return Array.isArray(data)?data:[]}
async function createPayment(planCode,billingCycle){if(role()!=="owner")throw new Error("Hanya Owner yang dapat membeli lisensi.");const {data,error}=await client().functions.invoke("ldm-license-payment",{body:{action:"create",plan_code:planCode,billing_cycle:billingCycle}});if(error)throw error;if(data?.error)throw new Error(data.error);return data}
async function checkPayment(paymentId){const {data,error}=await client().functions.invoke("ldm-license-payment",{body:{action:"check",payment_id:paymentId}});if(error)throw error;if(data?.error)throw new Error(data.error);return data}
async function developerOverview(){const {data,error}=await client().rpc("ldm_developer_license_overview");if(error)throw error;return data}
function formatRupiah(v){const n=Number(v||0);return new Intl.NumberFormat("id-ID",{style:"currency",currency:"IDR",maximumFractionDigits:0}).format(n)}
function formatDate(v){if(!v)return"-";try{return new Date(v).toLocaleString("id-ID",{timeZone:"Asia/Makassar",dateStyle:"medium",timeStyle:"short"})+" WITA"}catch{return String(v)}}
async function startRealtime(callback){if(realtimeChannel)return realtimeChannel;const ctx=await context();if(!ctx.network_id)return null;realtimeChannel=client().channel("ldm-license-v23").on("postgres_changes",{event:"*",schema:"public",table:"network_licenses",filter:`network_id=eq.${ctx.network_id}`},()=>callback?.()).on("postgres_changes",{event:"*",schema:"public",table:"license_payments",filter:`network_id=eq.${ctx.network_id}`},()=>callback?.()).subscribe();return realtimeChannel}
window.LDMLicense=Object.freeze({plans,context,startTrial,history,createPayment,checkPayment,developerOverview,formatRupiah,formatDate,startRealtime,role});
})();
