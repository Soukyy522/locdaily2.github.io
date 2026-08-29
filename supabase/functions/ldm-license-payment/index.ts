import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders={
  "Access-Control-Allow-Origin":"*",
  "Access-Control-Allow-Headers":"authorization,x-client-info,apikey,content-type",
  "Access-Control-Allow-Methods":"POST,OPTIONS",
};
function json(data:unknown,status=200){return new Response(JSON.stringify(data),{status,headers:{...corsHeaders,"Content-Type":"application/json"}})}
function env(name:string){return Deno.env.get(name)||""}
function basic(serverKey:string){return "Basic "+btoa(serverKey+":")}
function providerBase(mode:string){return mode==="production"?"https://app.midtrans.com":"https://app.sandbox.midtrans.com"}
function statusBase(mode:string){return mode==="production"?"https://api.midtrans.com":"https://api.sandbox.midtrans.com"}

Deno.serve(async(req)=>{
  if(req.method==="OPTIONS")return new Response("ok",{headers:corsHeaders});
  if(req.method!=="POST")return json({error:"Method not allowed"},405);
  try{
    const url=env("SUPABASE_URL");
    const anon=env("SUPABASE_ANON_KEY");
    const service=env("SUPABASE_SERVICE_ROLE_KEY");
    const serverKey=env("MIDTRANS_SERVER_KEY");
    const clientKey=env("MIDTRANS_CLIENT_KEY");
    const mode=(env("MIDTRANS_ENV")||"sandbox").toLowerCase()==="production"?"production":"sandbox";
    const authHeader=req.headers.get("Authorization")||"";
    if(!url||!anon||!service)return json({error:"Supabase Edge secrets belum lengkap."},500);
    if(!serverKey||!clientKey)return json({error:"MIDTRANS_SERVER_KEY / MIDTRANS_CLIENT_KEY belum diset pada Edge Secrets."},500);
    if(!authHeader.toLowerCase().startsWith("bearer "))return json({error:"Auth session wajib tersedia."},401);

    const userClient=createClient(url,anon,{global:{headers:{Authorization:authHeader}},auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});
    const admin=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});
    const {data:userData,error:userError}=await userClient.auth.getUser();
    if(userError||!userData.user)return json({error:"Session tidak valid."},401);
    const actor=userData.user;
    const {data:ctxData,error:ctxError}=await userClient.rpc("ldm_my_context");
    if(ctxError)throw ctxError;
    const ctx=Array.isArray(ctxData)?ctxData[0]:ctxData;
    if(!ctx||String(ctx.role||"").toLowerCase()!=="owner")return json({error:"Hanya Owner yang dapat melakukan pembayaran lisensi."},403);
    const {data:licCtx,error:licErr}=await userClient.rpc("ldm_license_context");
    if(licErr)throw licErr;
    const networkId=licCtx?.network_id;
    if(!networkId)return json({error:"Network lisensi tidak ditemukan."},409);

    const body=await req.json().catch(()=>({}));
    const action=String(body.action||"create").toLowerCase();

    if(action==="check"){
      const paymentId=String(body.payment_id||"").trim();
      if(!paymentId)return json({error:"payment_id wajib diisi."},400);
      const {data:payment,error:pErr}=await admin.from("license_payments").select("*").eq("id",paymentId).eq("network_id",networkId).maybeSingle();
      if(pErr)throw pErr;if(!payment)return json({error:"Payment tidak ditemukan."},404);
      const r=await fetch(`${statusBase(mode)}/v2/${encodeURIComponent(payment.provider_order_id)}/status`,{headers:{Authorization:basic(serverKey),Accept:"application/json"}});
      const result=await r.json().catch(()=>({}));
      if(!r.ok)return json({error:result?.status_message||"Midtrans status check gagal.",provider:result},502);
      const providerStatus=String(result.transaction_status||"");
      const paid=providerStatus==="settlement"||(providerStatus==="capture"&&String(result.fraud_status||"accept")!=="deny");
      const status=paid?"paid":providerStatus==="expire"?"expired":["deny","cancel"].includes(providerStatus)?"failed":"pending";
      const patch:any={provider_status:providerStatus,payment_type:result.payment_type||null,provider_transaction_id:result.transaction_id||null,status,raw_last_notification:result};
      if(paid)patch.paid_at=new Date().toISOString();
      const {error:uErr}=await admin.from("license_payments").update(patch).eq("id",payment.id);if(uErr)throw uErr;
      if(paid){const {error:aErr}=await admin.rpc("ldm_activate_license_from_payment",{p_payment_id:payment.id});if(aErr)throw aErr;}
      return json({ok:true,status,provider_status:providerStatus,payment_id:payment.id});
    }

    const planCode=String(body.plan_code||"").trim().toLowerCase();
    const cycle=String(body.billing_cycle||"").trim().toLowerCase();
    if(!["monthly","yearly","lifetime"].includes(cycle))return json({error:"Billing cycle tidak valid."},400);
    const {data:plan,error:planErr}=await admin.from("license_plans").select("*").eq("code",planCode).eq("active",true).maybeSingle();
    if(planErr)throw planErr;if(!plan)return json({error:"Paket tidak ditemukan."},404);
    if(plan.code==="lifetime"&&cycle!=="lifetime")return json({error:"Paket Lifetime hanya mendukung pembayaran lifetime."},400);
    if(plan.code!=="lifetime"&&cycle==="lifetime")return json({error:"Billing lifetime hanya tersedia pada paket Lifetime."},400);
    const amount=cycle==="monthly"?plan.monthly_price:cycle==="yearly"?plan.yearly_price:plan.lifetime_price;
    if(!amount||Number(amount)<=0)return json({error:"Harga paket/billing belum dikonfigurasi."},409);

    const orderId=`LDM-LIC-${Date.now()}-${crypto.randomUUID().replaceAll("-","").slice(0,8)}`.slice(0,50);
    const {data:payment,error:insertErr}=await admin.from("license_payments").insert({
      network_id:networkId,plan_id:plan.id,requested_by:actor.id,provider:"midtrans",
      provider_order_id:orderId,billing_cycle:cycle,amount:Number(amount),currency:"IDR",status:"pending"
    }).select("*").single();
    if(insertErr)throw insertErr;

    const origin=String(req.headers.get("origin")||"").replace(/\/$/,"");
    const payload:any={
      transaction_details:{order_id:orderId,gross_amount:Number(amount)},
      item_details:[{id:`${plan.code}-${cycle}`.slice(0,50),price:Number(amount),quantity:1,name:`LocDailyMar ${plan.name} ${cycle}`.slice(0,50)}],
      customer_details:{email:actor.email||undefined,first_name:ctx.username||"Owner"},
      custom_field1:String(networkId),custom_field2:String(plan.code),custom_field3:String(cycle)
    };
    if(origin.startsWith("https://")||origin.startsWith("http://localhost")||origin.startsWith("http://127.0.0.1")){
      payload.callbacks={finish:`${origin}/license.html?payment=finish`,error:`${origin}/payment-gateway.html?payment=error`,pending:`${origin}/license.html?payment=pending`};
    }
    const snapRes=await fetch(`${providerBase(mode)}/snap/v1/transactions`,{
      method:"POST",headers:{Authorization:basic(serverKey),Accept:"application/json","Content-Type":"application/json"},body:JSON.stringify(payload)
    });
    const snap=await snapRes.json().catch(()=>({}));
    if(!snapRes.ok||!snap.token){
      await admin.from("license_payments").update({status:"failed",provider_status:"create_failed",raw_last_notification:snap}).eq("id",payment.id);
      return json({error:snap?.error_messages?.join?.(", ")||snap?.status_message||"Gagal membuat transaksi Midtrans."},502);
    }
    await admin.from("license_payments").update({snap_token:snap.token,redirect_url:snap.redirect_url||null}).eq("id",payment.id);
    return json({ok:true,payment_id:payment.id,order_id:orderId,amount:Number(amount),snap_token:snap.token,redirect_url:snap.redirect_url||null,client_key:clientKey,environment:mode});
  }catch(error){console.error(error);return json({error:error?.message||String(error)},500)}
});
