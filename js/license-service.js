(function(){
"use strict";
let realtimeChannel=null;
function client(){if(!window.LDMSupabase)throw new Error("Supabase client belum tersedia.");return window.LDMSupabase.createClient()}
function role(){return String(localStorage.getItem("userRole")||localStorage.getItem("role")||"").trim().toLowerCase()}
async function plans(){const {data,error}=await client().rpc("ldm_license_plans");if(error)throw error;return Array.isArray(data)?data:[]}
async function context(){const {data,error}=await client().rpc("ldm_license_context");if(error)throw error;return data||{valid:false,status:"none"}}
async function contact(){const {data,error}=await client().rpc("ldm_license_contact");if(error)throw error;return data||{}}
async function startTrial(){if(role()!=="owner")throw new Error("Hanya Owner yang dapat memulai trial.");const {data,error}=await client().rpc("ldm_start_sederhana_trial");if(error)throw error;return data}
async function history(){if(role()!=="owner")return[];const {data,error}=await client().rpc("ldm_license_payment_history");if(error)throw error;return Array.isArray(data)?data:[]}
async function createWhatsappPayment(planCode,billingCycle){if(role()!=="owner")throw new Error("Hanya Owner yang dapat membeli lisensi.");const {data,error}=await client().rpc("ldm_create_whatsapp_payment_request",{p_plan_code:planCode,p_billing_cycle:billingCycle});if(error)throw error;if(data?.error)throw new Error(data.error);return data}
async function developerConfirmPayment(paymentId,note=""){const {data,error}=await client().rpc("ldm_developer_confirm_whatsapp_payment",{p_payment_id:paymentId,p_note:note||null});if(error)throw error;return data}
async function developerRejectPayment(paymentId,reason=""){const {data,error}=await client().rpc("ldm_developer_reject_whatsapp_payment",{p_payment_id:paymentId,p_reason:reason||null});if(error)throw error;return data}
async function developerOverview(){const {data,error}=await client().rpc("ldm_developer_license_overview");if(error)throw error;return data}
function formatRupiah(v){const n=Number(v||0);return new Intl.NumberFormat("id-ID",{style:"currency",currency:"IDR",maximumFractionDigits:0}).format(n)}
function formatDate(v){if(!v)return"-";try{return new Date(v).toLocaleString("id-ID",{timeZone:"Asia/Makassar",dateStyle:"medium",timeStyle:"short"})+" WITA"}catch{return String(v)}}
function whatsappUrl(phone,message){const clean=String(phone||"").replace(/\D/g,"");if(!/^\d{8,16}$/.test(clean))throw new Error("Nomor WhatsApp Developer belum valid.");return `https://wa.me/${clean}?text=${encodeURIComponent(String(message||""))}`}
async function startRealtime(callback){if(realtimeChannel)return realtimeChannel;const ctx=await context();if(!ctx.network_id)return null;realtimeChannel=client().channel("ldm-license-v23-1").on("postgres_changes",{event:"*",schema:"public",table:"network_licenses",filter:`network_id=eq.${ctx.network_id}`},()=>callback?.()).on("postgres_changes",{event:"*",schema:"public",table:"license_payments",filter:`network_id=eq.${ctx.network_id}`},()=>callback?.()).subscribe();return realtimeChannel}
window.LDMLicense=Object.freeze({plans,context,contact,startTrial,history,createWhatsappPayment,developerConfirmPayment,developerRejectPayment,developerOverview,formatRupiah,formatDate,whatsappUrl,startRealtime,role});
})();
