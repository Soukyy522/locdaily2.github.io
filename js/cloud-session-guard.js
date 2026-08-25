(function(){
    "use strict";

    const root =
        document.documentElement;

    root.classList.add(
        "ldm-cloud-auth-pending"
    );

    function addPendingStyle(){
        if(
            document.getElementById(
                "ldmCloudAuthPendingStyle"
            )
        ){
            return;
        }

        const style =
            document.createElement(
                "style"
            );

        style.id =
            "ldmCloudAuthPendingStyle";

        style.textContent =
            "html.ldm-cloud-auth-pending body{visibility:hidden!important;}";

        document.head.appendChild(
            style
        );
    }

    addPendingStyle();

    function failAuth(
        error
    ){
        console.error(
            "Cloud Auth Guard:",
            error
        );

        try{
            if(
                window.LDMCloudSession
            ){
                window.LDMCloudSession
                    .clearCompatibilityCache();
            }
        }catch(cacheError){
            console.warn(
                cacheError
            );
        }

        const message =
            encodeURIComponent(
                error &&
                error.message
                    ? error.message
                    : "Session cloud tidak valid."
            );

        window.location.replace(
            `index.html?cloudAuthError=${message}`
        );
    }

    function patchLogoutFunctions(){
        if(
            !window.LDMCloudSession
        ){
            return;
        }

        const cloudLogout =
            function(){
                return window
                    .LDMCloudSession
                    .logout(
                        "index.html"
                    );
            };

        [
            "secureLogout",
            "logout",
            "logoutSession"
        ].forEach(
            name => {
                if(
                    typeof window[name] ===
                    "function"
                ){
                    window[name] =
                        cloudLogout;
                }
            }
        );
    }

    async function boot(){
        if(
            !window.LDMSupabase ||
            !window.LDMSupabase
                .isConfigured()
        ){
            throw new Error(
                "Supabase belum dikonfigurasi."
            );
        }

        if(
            !window.LDMCloudSession
        ){
            throw new Error(
                "Cloud Session helper tidak termuat."
            );
        }

        const context =
            await window.LDMCloudSession
                .ensureAuthenticated({
                    registerDevice:
                        true
                });

        const role =
            window.LDMCloudSession
                .normalizeRole(
                    context.profile.role
                );

        if(
            ![
                "owner",
                "admin",
                "kasir"
            ].includes(role)
        ){
            throw new Error(
                "Role profile cloud tidak valid."
            );
        }

        patchLogoutFunctions();

        root.classList.remove(
            "ldm-cloud-auth-pending"
        );

        window.dispatchEvent(
            new CustomEvent(
                "ldm-cloud-auth-ready",
                {
                    detail:
                        context
                }
            )
        );

        return context;
    }

    window.LDMCloudGuard =
        Object.freeze({
            boot,
            patchLogoutFunctions
        });

    /*
     * Mulai sedini mungkin, sebelum DOMContentLoaded.
     * Ini membantu cache kompatibilitas tersedia sebelum
     * guard legacy halaman ikut berjalan.
     */
    boot()
        .then(
            () => {
                if(
                    document.readyState ===
                    "loading"
                ){
                    document.addEventListener(
                        "DOMContentLoaded",
                        patchLogoutFunctions,
                        {
                            once:
                                true
                        }
                    );
                }else{
                    patchLogoutFunctions();
                }

                window.addEventListener(
                    "load",
                    patchLogoutFunctions,
                    {
                        once:
                            true
                    }
                );
            }
        )
        .catch(
            failAuth
        );
})();
