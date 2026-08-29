import { createClient } from "npm:@supabase/supabase-js@2";

type JsonRecord=Record<string,unknown>;
type CorsHeaders=Record<string,string>;

function allowedOrigins():Set<string>{
  return new Set(String(Deno.env.get("LDM_LICENSE_ALLOWED_ORIGINS")||"").split(",").map(v=>v.trim()).filter(Boolean));
}

function corsFor(req:Request):CorsHeaders|null{
  const origin=req.headers.get("Origin")||"";
  const allowed=allowedOrigins();
  const allowNull=Deno.env.get("LDM_LICENSE_ALLOW_NULL_ORIGIN")==="true";
  if(origin&&!allowed.has("*")&&!allowed.has(origin)&&!(origin==="null"&&allowNull))return null;
  return {
    "Access-Control-Allow-Origin":origin||[...allowed][0]||"https://invalid.local",
    "Access-Control-Allow-Headers":"content-type",
    "Access-Control-Allow-Methods":"POST, OPTIONS",
    "Access-Control-Max-Age":"86400","Vary":"Origin"
  };
}

function respond(data:unknown,status:number,cors:CorsHeaders):Response{
  return new Response(JSON.stringify(data),{status,headers:{...cors,"Content-Type":"application/json; charset=utf-8","Cache-Control":"no-store"}});
}

function bytesToHex(bytes:Uint8Array):string{return Array.from(bytes).map(v=>v.toString(16).padStart(2,"0")).join("")}
function bytesToBase64Url(bytes:Uint8Array):string{
  let binary=""; bytes.forEach(v=>binary+=String.fromCharCode(v));
  return btoa(binary).replace(/\+/g,"-").replace(/\//g,"_").replace(/=+$/g,"");
}
async function sha256(value:string):Promise<string>{return bytesToHex(new Uint8Array(await crypto.subtle.digest("SHA-256",new TextEncoder().encode(value))))}
function randomToken():string{const bytes=new Uint8Array(32);crypto.getRandomValues(bytes);return bytesToBase64Url(bytes)}
function asObject(value:unknown):JsonRecord{return (Array.isArray(value)?value[0]:value||{}) as JsonRecord}

async function signCertificate(payload:JsonRecord):Promise<{payload:string;signature:string;algorithm:string}>{
  const raw=Deno.env.get("LDM_LICENSE_PRIVATE_JWK")||"";
  if(!raw)throw new Error("LICENSE_SIGNING_KEY_NOT_CONFIGURED");
  let jwk:JsonWebKey;
  try{jwk=JSON.parse(raw)}catch{throw new Error("LICENSE_SIGNING_KEY_INVALID")}
  const key=await crypto.subtle.importKey("jwk",jwk,{name:"ECDSA",namedCurve:"P-256"},false,["sign"])
    .catch(()=>{throw new Error("LICENSE_SIGNING_KEY_INVALID")});
  const payloadText=JSON.stringify(payload);
  const signature=await crypto.subtle.sign({name:"ECDSA",hash:"SHA-256"},key,new TextEncoder().encode(payloadText));
  return {payload:payloadText,signature:bytesToBase64Url(new Uint8Array(signature)),algorithm:"ES256"};
}

const KNOWN_ERRORS=[
  "LICENSE_KEY_INVALID","LICENSE_KEY_FORMAT_INVALID","LICENSE_EXPIRED","LICENSE_SUSPENDED","LICENSE_REVOKED","LICENSE_NOT_ACTIVE",
  "PLAN_INACTIVE","DEVICE_LIMIT_REACHED","STORE_LIMIT_REACHED","STORE_REFERENCE_INVALID","STORE_REFERENCE_MISMATCH",
  "ACTIVATION_NOT_FOUND","ACTIVATION_TOKEN_INVALID","ACTIVATION_ID_INVALID","INSTALLATION_ID_INVALID",
  "LICENSE_SIGNING_KEY_NOT_CONFIGURED","LICENSE_SIGNING_KEY_INVALID","LICENSE_EXPIRY_INVALID",
  "TRIAL_ALREADY_USED","TRIAL_IDENTITY_INVALID","TRIAL_PLAN_NOT_CONFIGURED","TRIAL_CONSENT_REQUIRED",
  "CUSTOMER_NAME_REQUIRED","CUSTOMER_EMAIL_INVALID","TOO_MANY_ATTEMPTS","TRIAL_IP_LIMIT_REACHED"
];
function safeCode(error:unknown):string{
  const message=String((error as {message?:string})?.message||error||"UNKNOWN_ERROR");
  return KNOWN_ERRORS.find(code=>message.includes(code))||"LICENSE_SERVER_ERROR";
}
function statusFor(code:string):number{
  if(["LICENSE_KEY_INVALID","ACTIVATION_NOT_FOUND","ACTIVATION_TOKEN_INVALID"].includes(code))return 401;
  if(["LICENSE_EXPIRED","LICENSE_SUSPENDED","LICENSE_REVOKED","LICENSE_NOT_ACTIVE","PLAN_INACTIVE"].includes(code))return 403;
  if(["DEVICE_LIMIT_REACHED","STORE_LIMIT_REACHED","TRIAL_ALREADY_USED"].includes(code))return 409;
  if(["TOO_MANY_ATTEMPTS","TRIAL_IP_LIMIT_REACHED"].includes(code))return 429;
  if(code==="LICENSE_SERVER_ERROR"||code.includes("SIGNING_KEY"))return 500;
  return 400;
}
function clientIp(req:Request):string{
  return String(req.headers.get("cf-connecting-ip")||req.headers.get("x-real-ip")||req.headers.get("x-forwarded-for")?.split(",")[0]||"unknown").trim();
}

Deno.serve(async(req:Request)=>{
  const requestId=crypto.randomUUID();
  const cors=corsFor(req);
  if(!cors)return new Response(JSON.stringify({error:"ORIGIN_NOT_ALLOWED",requestId}),{status:403,headers:{"Content-Type":"application/json"}});
  if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
  if(req.method!=="POST")return respond({error:"METHOD_NOT_ALLOWED",requestId},405,cors);

  const supabaseUrl=Deno.env.get("SUPABASE_URL")||"";
  const serviceKey=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")||"";
  const pepper=Deno.env.get("LDM_LICENSE_DEVICE_PEPPER")||"";
  if(!supabaseUrl||!serviceKey||pepper.length<32){
    console.error(requestId,"LICENSE_SERVER_NOT_CONFIGURED",{url:Boolean(supabaseUrl),serviceKey:Boolean(serviceKey),pepperLength:pepper.length});
    return respond({error:"LICENSE_SERVER_NOT_CONFIGURED",requestId,detail:"Periksa SUPABASE_SERVICE_ROLE_KEY dan LDM_LICENSE_DEVICE_PEPPER."},500,cors);
  }

  const admin=createClient(supabaseUrl,serviceKey,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});
  const body=await req.json().catch(()=>({})) as JsonRecord;
  const action=String(body.action||"").toLowerCase();

  if(action==="health"){
    return respond({ok:true,service:"ldm-license",version:"23.1.0",signingKeyConfigured:Boolean(Deno.env.get("LDM_LICENSE_PRIVATE_JWK")),allowedOrigins:[...allowedOrigins()].length,requestId},200,cors);
  }

  const installationId=String(body.installationId||"").trim();
  if(installationId.length<16||installationId.length>120)return respond({error:"INSTALLATION_ID_INVALID",requestId},400,cors);
  const installationHash=await sha256(`${pepper}:device:${installationId}`);
  const ipHash=await sha256(`${pepper}:ip:${clientIp(req)}`);
  let licenseId:string|null=null; let keyPrefix=""; let createdTrialId:string|null=null;

  async function log(outcome:"success"|"failed"|"blocked",reason:string,detail=""){
    await admin.from("license_validation_events").insert({request_id:requestId,license_id:licenseId,action:["activate","validate","deactivate","start_trial"].includes(action)?action:"validate",outcome,key_prefix:keyPrefix||null,installation_hash:installationHash,ip_hash:ipHash,reason:String(reason).slice(0,120),detail:String(detail).slice(0,240)}).then(()=>undefined).catch(()=>undefined);
  }

  try{
    if(!["activate","validate","deactivate","start_trial"].includes(action))return respond({error:"ACTION_INVALID",requestId},400,cors);

    const tenMinutesAgo=new Date(Date.now()-10*60*1000).toISOString();
    const {data:failures}=await admin.from("license_validation_events").select("id").eq("ip_hash",ipHash).in("outcome",["failed","blocked"]).gte("created_at",tenMinutesAgo).limit(12);
    if((failures||[]).length>=12){await log("blocked","TOO_MANY_ATTEMPTS");return respond({error:"TOO_MANY_ATTEMPTS",retryAfterSeconds:600,requestId},429,cors)}

    if(action==="start_trial"){
      const dayAgo=new Date(Date.now()-86400000).toISOString();
      const {data:trials}=await admin.from("license_validation_events").select("id").eq("ip_hash",ipHash).eq("action","start_trial").eq("outcome","success").gte("created_at",dayAgo).limit(3);
      if((trials||[]).length>=3){await log("blocked","TRIAL_IP_LIMIT_REACHED");return respond({error:"TRIAL_IP_LIMIT_REACHED",retryAfterSeconds:86400,requestId},429,cors)}
    }

    let license:JsonRecord; let activationToken=String(body.activationToken||"").trim();
    if(action==="activate"||action==="start_trial"){
      let licenseKey=String(body.licenseKey||"").trim().toUpperCase();
      const storeRef=String(body.storeRef||"").trim().toUpperCase();
      if(storeRef.length<3||storeRef.length>100)return respond({error:"STORE_REFERENCE_INVALID",requestId},400,cors);

      if(action==="start_trial"){
        const customerName=String(body.customerName||"").trim();
        const email=String(body.customerEmail||"").trim().toLowerCase();
        const whatsapp=String(body.whatsapp||"").trim();
        if(body.trialConsent!==true)return respond({error:"TRIAL_CONSENT_REQUIRED",requestId},400,cors);
        if(customerName.length<3||customerName.length>120)return respond({error:"CUSTOMER_NAME_REQUIRED",requestId},400,cors);
        if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)||email.length>160)return respond({error:"CUSTOMER_EMAIL_INVALID",requestId},400,cors);
        const {data,error}=await admin.rpc("ldm_start_trial",{p_customer_name:customerName,p_customer_email:email,p_identity_hash:await sha256(`${pepper}:trial-email:${email}`),p_installation_hash:installationHash,p_whatsapp:whatsapp||null,p_store_code:storeRef});
        if(error)throw error;
        const trial=asObject(data); licenseKey=String(trial.license_key||"").toUpperCase();
        licenseId=String(trial.license_id||"")||null; createdTrialId=licenseId;
      }

      if(!/^LDM-(?:[A-F0-9]{8}-){3}[A-F0-9]{8}$/.test(licenseKey)){
        keyPrefix=licenseKey.slice(0,12);await log("failed","LICENSE_KEY_FORMAT_INVALID");
        return respond({error:"LICENSE_KEY_FORMAT_INVALID",requestId},400,cors);
      }
      keyPrefix=licenseKey.slice(0,12); activationToken=randomToken();
      const {data,error}=await admin.rpc("ldm_license_activate",{p_key_hash:await sha256(licenseKey),p_installation_hash:installationHash,p_activation_token_hash:await sha256(activationToken),p_store_ref:storeRef,p_device_name:String(body.deviceName||"Perangkat LocDailyMar"),p_platform:String(body.platform||"browser"),p_app_version:String(body.appVersion||"unknown")});
      if(error)throw error; license=asObject(data);
    }else{
      if(activationToken.length<32){await log("failed","ACTIVATION_TOKEN_INVALID");return respond({error:"ACTIVATION_TOKEN_INVALID",requestId},401,cors)}
      if(action==="deactivate"){
        const {data,error}=await admin.rpc("ldm_license_deactivate",{p_activation_token_hash:await sha256(activationToken),p_installation_hash:installationHash});
        if(error)throw error;await log("success","DEACTIVATED");return respond({ok:true,result:data,requestId},200,cors);
      }
      const {data,error}=await admin.rpc("ldm_license_validate",{p_activation_token_hash:await sha256(activationToken),p_installation_hash:installationHash,p_store_ref:String(body.storeRef||"").trim().toUpperCase(),p_app_version:String(body.appVersion||"unknown")});
      if(error)throw error;license=asObject(data);
    }

    licenseId=String(license.license_id||"")||null;
    const now=Date.now(); const isLifetime=license.is_lifetime===true;
    const expiry=isLifetime?null:new Date(String(license.license_expires_at||"")).getTime();
    if(!isLifetime&&(!expiry||Number.isNaN(expiry)))throw new Error("LICENSE_EXPIRY_INVALID");
    const graceMs=Number(license.offline_grace_days||0)*86400000;
    const graceUntil=new Date(isLifetime?now+graceMs:Math.min(expiry as number,now+graceMs)).toISOString();
    const validationMinutes=Math.max(15,Math.min(360,Number(body.validationIntervalMinutes||60)));
    const certificate=await signCertificate({version:2,issuer:"LocDailyMar License Authority",licenseId,customerName:license.customer_name,planCode:license.plan_code,planName:license.plan_name,isLifetime,isTrial:license.is_trial===true,trialEndsAt:license.trial_ends_at||null,features:license.features,maxDevices:license.max_devices,maxStores:license.max_stores,storeRef:license.store_ref,installationId,issuedAt:new Date(now).toISOString(),onlineCheckAfter:new Date(now+validationMinutes*60000).toISOString(),offlineGraceUntil:graceUntil,licenseExpiresAt:isLifetime?null:new Date(expiry as number).toISOString()});
    await log("success",action==="start_trial"?"TRIAL_STARTED":action==="activate"?"ACTIVATED":"VALIDATED");
    return respond({ok:true,activationToken:["activate","start_trial"].includes(action)?activationToken:undefined,certificate,requestId},200,cors);
  }catch(error){
    const code=safeCode(error);const raw=String((error as {message?:string})?.message||error||"");
    console.error(requestId,"License request failed",code,raw);
    await log("failed",code,code==="LICENSE_SERVER_ERROR"?"Lihat Edge Function Logs untuk detail.":"");
    if(action==="start_trial"&&createdTrialId)await admin.from("licenses").delete().eq("id",createdTrialId).then(()=>undefined).catch(()=>undefined);
    return respond({error:code,requestId,detail:code==="LICENSE_SERVER_ERROR"?"Buka Supabase Edge Function Logs dan cari Request ID ini.":undefined},statusFor(code),cors);
  }
});
