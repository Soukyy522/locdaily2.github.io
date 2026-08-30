(function(){
    "use strict";

    const state={client:null,session:null,licenses:[],filtered:[],audit:[],selectedLicense:null};
    const $=selector=>document.querySelector(selector);
    const $$=selector=>Array.from(document.querySelectorAll(selector));
    const formatNumber=new Intl.NumberFormat("id-ID");
    const formatMoney=new Intl.NumberFormat("id-ID",{style:"currency",currency:"IDR",maximumFractionDigits:0});
    const formatDate=new Intl.DateTimeFormat("id-ID",{dateStyle:"medium",timeStyle:"short"});

    function text(value,fallback="-"){return value===null||value===undefined||value===""?fallback:String(value)}
    function date(value){if(!value)return "-";const parsed=new Date(value);return Number.isNaN(parsed.getTime())?"-":formatDate.format(parsed)}
    function money(value){return value===null||value===undefined?"-":formatMoney.format(Number(value)||0)}
    function setHidden(target,hidden){const node=typeof target==="string"?$(target):target;if(node)node.hidden=hidden}
    function setBusy(button,busy,label){if(!button)return;button.disabled=busy;if(busy){button.dataset.oldLabel=button.textContent;button.textContent=label||"Memproses…"}else if(button.dataset.oldLabel){button.textContent=button.dataset.oldLabel;delete button.dataset.oldLabel}}

    function notify(message,type="info"){
        const box=$("#adminNotice");
        if(!box)return;
        box.textContent=message;
        box.className=`notice ${type}`;
        box.hidden=false;
        clearTimeout(notify.timer);
        notify.timer=setTimeout(()=>{box.hidden=true},7000);
    }

    function configError(){
        const config=window.LDM_LICENSE_ADMIN_CONFIG||{};
        if(!config.enabled)return "Dashboard developer dinonaktifkan pada konfigurasi.";
        if(!/^https:\/\/[a-z0-9-]+\.supabase\.co$/i.test(String(config.supabaseUrl||""))||String(config.supabaseUrl).includes("PROJECT-REF"))return "Supabase URL dashboard developer belum dikonfigurasi.";
        if(!String(config.publishableKey||"").trim()||String(config.publishableKey).includes("MASUKKAN_"))return "Publishable Key project lisensi belum dikonfigurasi.";
        if(!/^https:\/\/[a-z0-9-]+\.supabase\.co\/functions\/v1\/ldm-license-admin$/i.test(String(config.functionUrl||""))||String(config.functionUrl).includes("PROJECT-REF"))return "Alamat Edge Function admin belum dikonfigurasi.";
        if(!window.supabase?.createClient)return "Library Supabase gagal dimuat. Periksa koneksi internet.";
        return "";
    }

    function readableError(code,detail){
        const messages={
            ADMIN_AUTH_REQUIRED:"Sesi developer sudah berakhir. Silakan masuk kembali.",
            ADMIN_ACCESS_DENIED:"Akun ini tidak terdaftar sebagai developer yang diizinkan.",
            ADMIN_ALLOWLIST_NOT_CONFIGURED:"Secret LDM_LICENSE_ADMIN_EMAILS belum disetel pada project lisensi.",
            LICENSE_RENEWAL_REQUIRED:"Lisensi sudah kedaluwarsa. Perpanjang dahulu memakai SQL perpanjangan.",
            ACTIVE_ACTIVATION_NOT_FOUND:"Perangkat sudah tidak aktif atau tidak ditemukan.",
            LICENSE_NOT_FOUND:"Data lisensi tidak ditemukan.",
            ORIGIN_NOT_ALLOWED:"Domain halaman ini belum dimasukkan ke LDM_LICENSE_ALLOWED_ORIGINS.",
            LICENSE_ADMIN_SERVER_ERROR:"Server admin mengalami kesalahan. Periksa Edge Function Logs.",
            LICENSE_ADMIN_SERVER_NOT_CONFIGURED:"Konfigurasi server admin belum lengkap."
        };
        return messages[code]||detail||code||"Permintaan gagal diproses.";
    }

    async function callAdmin(action,payload={}){
        if(!state.session?.access_token)throw new Error("ADMIN_AUTH_REQUIRED");
        let response;
        try{
            response=await fetch(window.LDM_LICENSE_ADMIN_CONFIG.functionUrl,{
                method:"POST",
                headers:{"Content-Type":"application/json","Authorization":`Bearer ${state.session.access_token}`,"apikey":window.LDM_LICENSE_ADMIN_CONFIG.publishableKey},
                body:JSON.stringify({action,...payload}),
                cache:"no-store"
            });
        }catch(error){throw new Error("NETWORK_ERROR")}
        const data=await response.json().catch(()=>({}));
        if(!response.ok){const error=new Error(readableError(data.error,data.detail));error.code=data.error;error.requestId=data.requestId;throw error}
        return data;
    }

    function effectiveStatus(item){
        if(["active","suspended"].includes(item.status)&&item.is_lifetime!==true&&item.expires_at&&new Date(item.expires_at).getTime()<=Date.now())return "expired";
        return text(item.status,"unknown").toLowerCase();
    }

    function statusLabel(status){return ({active:"Aktif",suspended:"Ditangguhkan",expired:"Kedaluwarsa",revoked:"Dicabut"})[status]||status}
    function cycleLabel(cycle){return ({monthly:"Bulanan",yearly:"Tahunan",lifetime:"Selamanya",trial:"Trial"})[cycle]||text(cycle)}

    function renderSummary(summary={}){
        const values={total:summary.total||0,active:summary.active||0,trial:summary.trial||0,suspended:summary.suspended||0,expired:summary.expired||0,devices:summary.devices||0};
        Object.entries(values).forEach(([key,value])=>{const node=$(`[data-stat="${key}"]`);if(node)node.textContent=formatNumber.format(Number(value)||0)});
    }

    function licenseRow(item){
        const status=effectiveStatus(item);
        const canSuspend=status==="active";
        const canActivate=status==="suspended";
        const storeUsage=`${Number(item.active_stores||0)}/${Number(item.max_stores||0)}`;
        const deviceUsage=`${Number(item.active_devices||0)}/${Number(item.max_devices||0)}`;
        const actions=[
            `<button class="table-btn" data-action="devices" data-id="${item.id}">Perangkat</button>`,
            canSuspend?`<button class="table-btn danger" data-action="suspend" data-id="${item.id}">Tangguhkan</button>`:"",
            canActivate?`<button class="table-btn success" data-action="activate" data-id="${item.id}">Aktifkan</button>`:""
        ].join("");
        return `<tr>
            <td><strong>${escapeHtml(text(item.customer_name))}</strong><span>${escapeHtml(text(item.customer_email))}</span><small>${escapeHtml(text(item.customer_whatsapp))}</small></td>
            <td><strong>${escapeHtml(text(item.plan_name,item.plan_code))}</strong><span>${escapeHtml(cycleLabel(item.billing_cycle))}${item.is_trial===true?" · 14 hari":""}</span><small>${escapeHtml(money(item.price_paid))}</small></td>
            <td><span class="status ${status}">${escapeHtml(statusLabel(status))}</span><small>${escapeHtml(text(item.license_key_masked))}</small></td>
            <td><strong>${escapeHtml(text(item.primary_store_code))}</strong><span>Toko ${storeUsage} · Perangkat ${deviceUsage}</span></td>
            <td><strong>${item.is_lifetime===true?"Tidak berakhir":escapeHtml(date(item.expires_at))}</strong><span>Terakhir aktif: ${escapeHtml(date(item.last_seen_at))}</span></td>
            <td><div class="row-actions">${actions}</div></td>
        </tr>`;
    }

    function escapeHtml(value){
        return String(value).replace(/[&<>'"]/g,char=>({"&":"&amp;","<":"&lt;",">":"&gt;","'":"&#39;",'"':"&quot;"})[char]);
    }

    function applyFilters(){
        const query=text($("#licenseSearch")?.value,"").trim().toLowerCase();
        const status=$("#statusFilter")?.value||"all";
        const plan=$("#planFilter")?.value||"all";
        state.filtered=state.licenses.filter(item=>{
            const haystack=[item.customer_name,item.customer_email,item.customer_whatsapp,item.primary_store_code,item.plan_name,item.plan_code,item.license_key_masked].map(value=>text(value,"").toLowerCase()).join(" ");
            return (!query||haystack.includes(query))&&(status==="all"||effectiveStatus(item)===status)&&(plan==="all"||item.plan_code===plan);
        });
        renderLicenses();
    }

    function renderLicenses(){
        const body=$("#licenseRows");
        if(!body)return;
        body.innerHTML=state.filtered.length?state.filtered.map(licenseRow).join(""):'<tr><td colspan="6" class="empty">Tidak ada lisensi yang cocok dengan pencarian.</td></tr>';
        $("#resultCount").textContent=`${formatNumber.format(state.filtered.length)} dari ${formatNumber.format(state.licenses.length)} lisensi`;
    }

    function renderAudit(){
        const list=$("#auditList");
        if(!list)return;
        const labels={license_suspended:"Lisensi ditangguhkan",license_activated:"Lisensi diaktifkan",device_deactivated:"Perangkat dinonaktifkan"};
        list.innerHTML=state.audit.length?state.audit.map(item=>`<li><span class="audit-dot"></span><div><strong>${escapeHtml(labels[item.action]||item.action)}</strong><span>${escapeHtml(text(item.actor_email))} · ${escapeHtml(date(item.created_at))}</span></div></li>`).join(""):'<li class="empty">Belum ada aktivitas admin.</li>';
    }

    async function loadDashboard(showMessage=false){
        const button=$("#refreshButton");
        setBusy(button,true,"Memuat…");
        try{
            const data=await callAdmin("dashboard");
            state.licenses=data.licenses||[];
            state.audit=data.audit||[];
            renderSummary(data.summary);
            applyFilters();
            renderAudit();
            $("#lastRefresh").textContent=`Diperbarui ${formatDate.format(new Date())}`;
            if(showMessage)notify("Data lisensi berhasil diperbarui.","success");
        }catch(error){
            notify(`${error.message}${error.requestId?` (Request ID: ${error.requestId})`:""}`,"error");
            if(error.code==="ADMIN_AUTH_REQUIRED")await signOut(false);
        }finally{setBusy(button,false)}
    }

    function renderSession(){
        const signedIn=Boolean(state.session);
        setHidden("#dashboardSession",!signedIn);
        setHidden("#loginView",signedIn);
        setHidden("#dashboardView",!signedIn);
        if(signedIn){$("#adminIdentity").textContent=state.session.user?.email||"Developer";loadDashboard()}
    }

    async function signIn(event){
        event.preventDefault();
        const button=$("#loginButton");
        setBusy(button,true,"Memeriksa…");
        try{
            const email=$("#adminEmail").value.trim().toLowerCase();
            const password=$("#adminPassword").value;
            if(!email||!password)throw new Error("Isi email dan password developer.");
            const {data,error}=await state.client.auth.signInWithPassword({email,password});
            if(error)throw error;
            state.session=data.session;
            $("#adminPassword").value="";
            notify("Login developer berhasil.","success");
            renderSession();
        }catch(error){notify(error.message||"Login gagal.","error")}
        finally{setBusy(button,false)}
    }

    async function signOut(showMessage=true){
        await state.client?.auth.signOut().catch(()=>undefined);
        state.session=null;state.licenses=[];state.filtered=[];state.audit=[];
        renderSession();
        if(showMessage)notify("Anda sudah keluar dari dashboard developer.","success");
    }

    async function changeStatus(id,status,button){
        const item=state.licenses.find(row=>row.id===id);if(!item)return;
        const verb=status==="suspended"?"menangguhkan":"mengaktifkan kembali";
        if(!window.confirm(`Yakin ingin ${verb} lisensi ${item.customer_name}?`))return;
        setBusy(button,true,"Memproses…");
        try{
            await callAdmin("set_status",{licenseId:id,status,reason:status==="suspended"?"Ditangguhkan melalui dashboard developer":"Diaktifkan kembali melalui dashboard developer"});
            notify(`Lisensi ${item.customer_name} berhasil ${status==="suspended"?"ditangguhkan":"diaktifkan"}.`,"success");
            await loadDashboard();
        }catch(error){notify(`${error.message}${error.requestId?` (Request ID: ${error.requestId})`:""}`,"error")}
        finally{setBusy(button,false)}
    }

    async function openDevices(id){
        const item=state.licenses.find(row=>row.id===id);if(!item)return;
        state.selectedLicense=item;
        $("#deviceCustomer").textContent=item.customer_name;
        $("#deviceRows").innerHTML='<tr><td colspan="6" class="empty">Memuat perangkat…</td></tr>';
        if(!$("#deviceDialog").open)$("#deviceDialog").showModal();
        try{
            const data=await callAdmin("list_devices",{licenseId:id});
            const devices=data.devices||[];
            $("#deviceRows").innerHTML=devices.length?devices.map(device=>`<tr>
                <td><strong>${escapeHtml(text(device.device_name))}</strong><span>${escapeHtml(text(device.platform))} · ${escapeHtml(text(device.app_version))}</span></td>
                <td>${escapeHtml(text(device.store_ref))}</td>
                <td><span class="status ${escapeHtml(device.status)}">${escapeHtml(statusLabel(device.status))}</span></td>
                <td>${escapeHtml(date(device.first_activated_at))}</td>
                <td>${escapeHtml(date(device.last_validated_at))}</td>
                <td>${device.status==="active"?`<button class="table-btn danger" data-action="deactivate-device" data-id="${device.id}">Nonaktifkan</button>`:"-"}</td>
            </tr>`).join(""):'<tr><td colspan="6" class="empty">Belum ada perangkat pada lisensi ini.</td></tr>';
        }catch(error){$("#deviceRows").innerHTML=`<tr><td colspan="6" class="empty error-text">${escapeHtml(error.message)}</td></tr>`}
    }

    async function deactivateDevice(id,button){
        if(!window.confirm("Nonaktifkan perangkat ini? Customer harus melakukan aktivasi ulang bila ingin memakainya kembali."))return;
        setBusy(button,true,"Memproses…");
        try{
            await callAdmin("deactivate_device",{activationId:id});
            notify("Perangkat lama berhasil dinonaktifkan.","success");
            await openDevices(state.selectedLicense.id);
            await loadDashboard();
        }catch(error){notify(`${error.message}${error.requestId?` (Request ID: ${error.requestId})`:""}`,"error")}
        finally{setBusy(button,false)}
    }

    function bindEvents(){
        $("#loginForm").addEventListener("submit",signIn);
        $("#logoutButton").addEventListener("click",()=>signOut());
        $("#refreshButton").addEventListener("click",()=>loadDashboard(true));
        $("#licenseSearch").addEventListener("input",applyFilters);
        $("#statusFilter").addEventListener("change",applyFilters);
        $("#planFilter").addEventListener("change",applyFilters);
        $("#closeDeviceDialog").addEventListener("click",()=>$("#deviceDialog").close());
        $("#licenseRows").addEventListener("click",event=>{
            const button=event.target.closest("button[data-action]");if(!button)return;
            if(button.dataset.action==="devices")openDevices(button.dataset.id);
            if(button.dataset.action==="suspend")changeStatus(button.dataset.id,"suspended",button);
            if(button.dataset.action==="activate")changeStatus(button.dataset.id,"active",button);
        });
        $("#deviceRows").addEventListener("click",event=>{
            const button=event.target.closest('button[data-action="deactivate-device"]');
            if(button)deactivateDevice(button.dataset.id,button);
        });
    }

    async function init(){
        bindEvents();
        const error=configError();
        if(error){setHidden("#loginView",false);$("#configWarning").textContent=error;$("#configWarning").hidden=false;$("#loginButton").disabled=true;return}
        const config=window.LDM_LICENSE_ADMIN_CONFIG;
        state.client=window.supabase.createClient(config.supabaseUrl,config.publishableKey,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:false}});
        const {data}=await state.client.auth.getSession();
        state.session=data.session||null;
        state.client.auth.onAuthStateChange((_event,session)=>{state.session=session||null});
        renderSession();
    }

    document.addEventListener("DOMContentLoaded",init,{once:true});
})();
