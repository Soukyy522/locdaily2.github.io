import { createClient } from "npm:@supabase/supabase-js@2";
function json(data:unknown,status=200){return new Response(JSON.stringify(data),{status,headers:{"Content-Type":"application/json"}})}
function env(name:string){return Deno.env.get(name)||""}
async function sha512(value:string){const data=new TextEncoder().encode(value);const digest=await crypto.subtle.digest("SHA-512",data);return Array.from(new Uint8Array(digest)).map(b=>b.toString(16).padStart(2,"0")).join("")}
Deno.serve(async(req)=>{
  if(req.method!=="POST")return json({error:"Method not allowed"},405);
  try{
    const url=env("SUPABASE_URL"),service=env("SUPABASE_SERVICE_ROLE_KEY"),serverKey=env("MIDTRANS_SERVER_KEY");
    if(!url||!service||!serverKey)return json({error:"Server secrets belum lengkap."},500);
    const body=await req.json().catch(()=>null);if(!body)return json({error:"JSON body invalid."},400);
    const orderId=String(body.order_id||""),statusCode=String(body.status_code||""),gross=String(body.gross_amount||""),signature=String(body.signature_key||"");
    if(!orderId||!statusCode||!gross||!signature)return json({error:"Notification field tidak lengkap."},400);
    const expected=await sha512(orderId+statusCode+gross+serverKey);
    if(expected.toLowerCase()!==signature.toLowerCase())return json({error:"Invalid Midtrans signature."},401);

    const admin=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});
    const {data:payment,error:pErr}=await admin.from("license_payments").select("*").eq("provider_order_id",orderId).maybeSingle();
    if(pErr)throw pErr;if(!payment)return json({error:"Order tidak dikenal."},404);
    const notifiedAmount=Math.round(Number(gross));
    if(!Number.isFinite(notifiedAmount)||notifiedAmount!==Number(payment.amount))return json({error:"Amount mismatch."},409);

    const providerStatus=String(body.transaction_status||"");
    const fraud=String(body.fraud_status||"");
    const paid=providerStatus==="settlement"||(providerStatus==="capture"&&fraud!=="deny");
    let localStatus="pending";
    if(paid)localStatus="paid";
    else if(providerStatus==="expire")localStatus="expired";
    else if(["deny","cancel"].includes(providerStatus))localStatus="failed";
    else if(["refund","partial_refund"].includes(providerStatus))localStatus="refunded";

    const patch:any={status:localStatus,provider_status:providerStatus,payment_type:body.payment_type||null,provider_transaction_id:body.transaction_id||null,raw_last_notification:body};
    if(paid&&!payment.paid_at)patch.paid_at=new Date().toISOString();
    const {error:uErr}=await admin.from("license_payments").update(patch).eq("id",payment.id);if(uErr)throw uErr;
    if(paid){const {error:aErr}=await admin.rpc("ldm_activate_license_from_payment",{p_payment_id:payment.id});if(aErr)throw aErr;}
    return json({ok:true,order_id:orderId,status:localStatus});
  }catch(error){console.error(error);return json({error:error?.message||String(error)},500)}
});
