(function(){
    "use strict";

    const NAV_VERSION="22.1";
    const ROUTES=[
        {page:"dashboard.html",icon:"📊",label:"Dashboard",group:"Utama",roles:["owner","admin","kasir"],quick:true},
        {page:"absensi.html",icon:"📝",label:"Absensi",group:"Utama",roles:["owner","admin","kasir"]},
        {page:"kasir.html",icon:"💵",label:"Kasir",group:"Utama",roles:["owner","admin","kasir"],quick:true},
        {page:"retur.html",icon:"↩️",label:"Retur",group:"Utama",roles:["owner","admin","kasir"]},
        {page:"barang.html",icon:"📦",label:"Barang",group:"Inventori",roles:["owner","admin"]},
        {page:"kartu-stok.html",icon:"📒",label:"Kartu Stok",group:"Inventori",roles:["owner","admin","kasir"]},
        {page:"stock-opname.html",icon:"📋",label:"Stock Opname",group:"Inventori",roles:["owner","admin","kasir"]},
        {page:"multi-store.html",icon:"⇄",label:"Multi-Toko & Transfer",group:"Inventori",roles:["owner","admin"],quick:true},
        {page:"supplier.html",icon:"🏢",label:"Supplier",group:"Supplier & Pembelian",roles:["owner","admin"]},
        {page:"Purchase-Order.html",icon:"🛒",label:"Purchase Order",group:"Supplier & Pembelian",roles:["owner","admin"]},
        {page:"goods.receipt.html",icon:"📥",label:"Goods Receipt",group:"Supplier & Pembelian",roles:["owner","admin"]},
        {page:"laporan.html",icon:"📑",label:"Laporan",group:"Keuangan & Laporan",roles:["owner","admin","kasir"],quick:true},
        {page:"pengeluaran.html",icon:"💸",label:"Pengeluaran",group:"Keuangan & Laporan",roles:["owner","admin"]},
        {page:"shift-closing.html",icon:"🔒",label:"Closing Shift",group:"Closing & Data",roles:["owner","admin"]},
        {page:"eod.html",icon:"🌙",label:"End of Day",group:"Closing & Data",roles:["owner","admin"]},
        {page:"backup%20%26%20restore.html",icon:"💾",label:"Backup & Restore",group:"Closing & Data",roles:["owner","admin"]},
        {page:"pwa-settings.html",icon:"📲",label:"Aplikasi & Update",group:"Sistem",roles:["owner","admin","kasir"]},
        {page:"recovery-center.html",icon:"🛟",label:"Recovery Center",group:"Sistem",roles:["owner","admin","kasir"]},
        {page:"qa-security-performance.html",icon:"🧪",label:"QA & Security",group:"Sistem",roles:["owner"]}
    ];

    const GROUP_META={
        "Utama":"⚡",
        "Inventori":"📦",
        "Supplier & Pembelian":"🏢",
        "Keuangan & Laporan":"📑",
        "Closing & Data":"🔐",
        "Sistem":"⚙️"
    };

    function normalizeRole(value){
        const role=String(value||"").trim().toLowerCase();
        if(role==="administrator")return "admin";
        if(role==="cashier")return "kasir";
        return role;
    }

    function currentRole(){return normalizeRole(localStorage.getItem("userRole")||localStorage.getItem("role"))}

    function currentPage(){
        let page=location.pathname.split("/").pop()||"dashboard.html";
        try{page=decodeURIComponent(page)}catch(error){}
        return String(page||"dashboard.html").toLowerCase();
    }

    function normalizedPage(value){
        let page=String(value||"").split("#")[0].split("?")[0].replace(/^\.\//,"");
        try{page=decodeURIComponent(page)}catch(error){}
        return page.split("/").pop().toLowerCase();
    }

    function esc(value){
        return String(value==null?"":value).replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/"/g,"&quot;").replace(/'/g,"&#039;");
    }

    function sessionName(){
        return String(localStorage.getItem("activeUsername")||localStorage.getItem("loggedInUser")||localStorage.getItem("username")||"Pengguna");
    }

    function storeName(){return String(localStorage.getItem("ldmCloudStoreName")||"Toko belum terhubung")}
    function visibleRoutes(role){return ROUTES.filter(route=>route.roles.includes(role))}
    function isActive(route){return currentPage()===normalizedPage(route.page)}

    function addStylesheet(){
        if(document.getElementById("ldmGlobalNavigationCSS"))return;
        const link=document.createElement("link");
        link.id="ldmGlobalNavigationCSS";
        link.rel="stylesheet";
        link.href=`css/global-responsive-navigation.css?v=${NAV_VERSION}`;
        document.head.appendChild(link);
    }

    function parseTheme(){
        try{return JSON.parse(localStorage.getItem("headerConfig")||"null")||{}}
        catch(error){return {}}
    }

    function applySharedTheme(){
        const config=parseTheme();
        const root=document.documentElement;
        const headerColor=config.warnaBgHeader||"#0d2240";
        const accent=config.warnaSubJudul||"#ffc107";
        const dark=Boolean(config.darkMode);
        document.body.classList.toggle("dark-mode",dark);
        root.style.setProperty("--app-font",config.fontFamily||"'Poppins', sans-serif");
        root.style.setProperty("--brand-font",config.brandFontFamily||config.fontFamily||"'Poppins', sans-serif");
        root.style.setProperty("--bg-primary",config.bgPrimary||(dark?"#0f172a":"#f4f6f9"));
        root.style.setProperty("--bg-secondary",config.bgSecondary||(dark?"#1e293b":"#ffffff"));
        root.style.setProperty("--nav-desktop-bg",dark&&headerColor==="#0d2240"?"#1e293b":headerColor);
        root.style.setProperty("--accent-color",accent);
        document.querySelectorAll("[data-ldm-brand-title]").forEach(node=>{
            node.textContent=config.judul||"LocDailyMar";
            if(config.warnaJudul)node.style.color=config.warnaJudul;
            if(config.warnaOutline)node.style.textShadow=`1px 1px 0 ${config.warnaOutline}`;
        });
        document.querySelectorAll("[data-ldm-brand-subtitle]").forEach(node=>{
            node.textContent=config.subJudul||"Multi-Toko & Transfer Stok";
            node.style.color=accent;
        });
        document.querySelectorAll("[data-ldm-brand-logo]").forEach(node=>{
            if(config.logoData){node.src=config.logoData;node.style.display="block"}
            else node.style.display="none";
        });
    }

    function routeLink(route,mode){
        const klass=mode==="mobile"?"ldm-global-mobile-link":"ldm-global-link";
        return `<a href="${route.page}" class="${klass}${isActive(route)?" active":""}" data-ldm-route="${esc(route.page)}"><span class="ldm-global-icon" aria-hidden="true">${route.icon}</span><span>${esc(route.label)}</span></a>`;
    }

    function groupedHTML(routes,mode){
        const grouped={};
        routes.forEach(route=>{
            if(!grouped[route.group])grouped[route.group]=[];
            grouped[route.group].push(route);
        });
        return Object.entries(grouped).map(([group,items])=>{
            if(mode==="mobile")return `<section class="ldm-global-mobile-group"><div class="ldm-global-mobile-label"><span>${GROUP_META[group]||"•"}</span><span>${esc(group)}</span></div>${items.map(item=>routeLink(item,"mobile")).join("")}</section>`;
            return `<section class="ldm-global-group"><div class="ldm-global-group-title"><span>${GROUP_META[group]||"•"}</span><span>${esc(group)}</span></div><div class="ldm-global-links">${items.map(item=>routeLink(item,"desktop")).join("")}</div></section>`;
        }).join("");
    }

    function ensureMega(role){
        if(document.getElementById("ldmMegaNavShell"))return;
        let shell=document.getElementById("ldmGlobalMegaNav");
        if(shell){document.documentElement.classList.add("ldm-global-mega-ready");return}
        const routes=visibleRoutes(role);
        if(!routes.length)return;
        const quick=routes.filter(route=>route.quick).map(route=>`<a href="${route.page}" class="${isActive(route)?"active":""}"><span>${route.icon}</span><span>${esc(route.label)}</span></a>`).join("");
        shell=document.createElement("div");
        shell.id="ldmGlobalMegaNav";
        shell.className="ldm-global-mega";
        shell.innerHTML=`<nav class="ldm-global-mega-bar" aria-label="Navigasi utama desktop"><button type="button" class="ldm-global-mega-trigger" aria-expanded="false" aria-controls="ldmGlobalMegaPanel"><span>☷</span><span>Mega Menu</span><span class="ldm-global-mega-arrow">▼</span></button><div class="ldm-global-mega-quick">${quick}</div><div class="ldm-global-mega-session"><span class="ldm-global-store" data-ldm-store-name>${esc(storeName())}</span><span class="ldm-global-role">👤 ${esc(role)}</span></div><div class="ldm-global-mega-panel" id="ldmGlobalMegaPanel"><div class="ldm-global-panel-head"><div><strong>Navigasi LocDailyMar</strong><p>Seluruh menu yang diizinkan untuk role Anda tersedia di sini.</p></div><button type="button" class="ldm-global-panel-close">✕ Tutup</button></div><div class="ldm-global-mega-grid">${groupedHTML(routes,"desktop")}</div></div></nav>`;
        const app=document.querySelector(".app-layout");
        const main=app&&app.querySelector(".main-content");
        if(app&&main)app.insertBefore(shell,main);else document.body.insertAdjacentElement("afterbegin",shell);
        const trigger=shell.querySelector(".ldm-global-mega-trigger");
        const close=shell.querySelector(".ldm-global-panel-close");
        const setOpen=open=>{shell.classList.toggle("open",Boolean(open));trigger.setAttribute("aria-expanded",open?"true":"false")};
        trigger.addEventListener("click",event=>{event.stopPropagation();setOpen(!shell.classList.contains("open"))});
        close.addEventListener("click",()=>{setOpen(false);trigger.focus()});
        document.addEventListener("click",event=>{if(!shell.contains(event.target))setOpen(false)});
        document.addEventListener("keydown",event=>{if(event.key==="Escape")setOpen(false)});
        let hoverTimer=0;
        shell.addEventListener("mouseenter",()=>{if(matchMedia("(min-width:900px)").matches){clearTimeout(hoverTimer);setOpen(true)}});
        shell.addEventListener("mouseleave",()=>{if(matchMedia("(min-width:900px)").matches){clearTimeout(hoverTimer);hoverTimer=setTimeout(()=>setOpen(false),180)}});
        document.documentElement.classList.add("ldm-global-mega-ready");
    }

    function sidebarLink(route){
        const link=document.createElement("a");
        link.href=route.page;
        link.className=`nav-item ldm-system-nav-item${isActive(route)?" active":""}`;
        link.dataset.ldmSystemNav=route.page;
        link.dataset.roleAccess=route.roles.join(",");
        link.innerHTML=`<span aria-hidden="true">${route.icon}</span> ${esc(route.label)}`;
        return link;
    }

    function enhanceLegacySidebars(role){
        const visible=visibleRoutes(role);
        document.querySelectorAll(".nav-bar").forEach(nav=>{
            const existing=new Set([...nav.querySelectorAll("a[href]")].map(link=>normalizedPage(link.getAttribute("href"))));
            visible.forEach(route=>{if(!existing.has(normalizedPage(route.page)))nav.appendChild(sidebarLink(route))});
            nav.querySelectorAll("a[href]").forEach(link=>{
                const route=ROUTES.find(item=>normalizedPage(item.page)===normalizedPage(link.getAttribute("href")));
                if(!route)return;
                const denied=!route.roles.includes(role);
                link.dataset.ldmRoleHidden=denied?"true":"false";
                link.hidden=denied;
                link.setAttribute("aria-hidden",denied?"true":"false");
                if(denied)link.setAttribute("tabindex","-1");else link.removeAttribute("tabindex");
            });
        });
    }

    function ensureMobileDrawer(role){
        if(document.querySelector(".nav-bar")||document.getElementById("ldmGlobalMobileDrawer"))return;
        const routes=visibleRoutes(role);
        if(!routes.length)return;
        const overlay=document.createElement("div");
        overlay.id="ldmGlobalMobileOverlay";
        overlay.className="ldm-global-mobile-overlay";
        overlay.setAttribute("aria-hidden","true");
        const drawer=document.createElement("aside");
        drawer.id="ldmGlobalMobileDrawer";
        drawer.className="ldm-global-mobile-drawer";
        drawer.setAttribute("aria-label","Menu navigasi HP");
        drawer.innerHTML=`<div class="ldm-global-mobile-head"><strong>☰ Menu LocDailyMar</strong><button type="button" class="ldm-global-mobile-close" aria-label="Tutup menu">✕</button></div><div class="ldm-global-mobile-context"><strong>${esc(sessionName())} · ${esc(role)}</strong><span data-ldm-store-name>${esc(storeName())}</span></div>${groupedHTML(routes,"mobile")}`;
        document.body.append(overlay,drawer);
        const close=()=>{
            drawer.classList.remove("open");overlay.classList.remove("open");document.body.classList.remove("ldm-global-menu-open");
            document.querySelectorAll("[data-ldm-menu-toggle]").forEach(button=>button.setAttribute("aria-expanded","false"));
        };
        const open=()=>{
            drawer.classList.add("open");overlay.classList.add("open");document.body.classList.add("ldm-global-menu-open");
            document.querySelectorAll("[data-ldm-menu-toggle]").forEach(button=>button.setAttribute("aria-expanded","true"));
            drawer.querySelector("a")?.focus();
        };
        drawer.querySelector(".ldm-global-mobile-close").addEventListener("click",close);
        overlay.addEventListener("click",close);
        drawer.querySelectorAll("a").forEach(link=>link.addEventListener("click",close));
        document.addEventListener("keydown",event=>{if(event.key==="Escape")close()});
        let buttons=[...document.querySelectorAll("[data-ldm-menu-toggle]")];
        if(!buttons.length){
            const floating=document.createElement("button");
            floating.type="button";
            floating.className="ldm-global-floating-toggle";
            floating.dataset.ldmMenuToggle="true";
            floating.setAttribute("aria-label","Buka menu navigasi");
            floating.setAttribute("aria-expanded","false");
            floating.textContent="☰";
            document.body.appendChild(floating);
            buttons=[floating];
        }
        buttons.forEach(button=>button.addEventListener("click",open));
    }

    function refreshContext(){document.querySelectorAll("[data-ldm-store-name]").forEach(node=>{node.textContent=storeName()})}

    function render(){
        addStylesheet();
        applySharedTheme();
        const role=currentRole();
        document.documentElement.dataset.ldmRole=role;
        if(!role)return false;
        enhanceLegacySidebars(role);
        ensureMega(role);
        ensureMobileDrawer(role);
        refreshContext();
        return true;
    }

    function boot(){
        let attempt=0;
        const run=()=>{attempt+=1;if(render()||attempt>=12)return;setTimeout(run,250)};
        run();
    }

    if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",boot,{once:true});else boot();
    window.addEventListener("storage",event=>{if(["headerConfig","userRole","role","ldmCloudStoreName"].includes(event.key)){applySharedTheme();refreshContext()}});
    window.addEventListener("ldm-cloud-session-ready",()=>{render();refreshContext()});
    window.LDMGlobalNavigation={render,applySharedTheme,refreshContext};
})();
