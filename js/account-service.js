(function(){
    "use strict";

    const CHANNEL_NAME =
        "ldm-cloud-accounts-v14";

    let channel = null;

    function client(){
        if(
            !window.LDMSupabase ||
            typeof window.LDMSupabase.createClient !== "function"
        ){
            throw new Error(
                "Supabase client belum tersedia."
            );
        }

        return window.LDMSupabase
            .createClient();
    }

    async function ownerContext(){
        if(!window.LDMCloudSession){
            throw new Error(
                "Cloud Session belum tersedia."
            );
        }

        const context =
            await window.LDMCloudSession
                .ensureAuthenticated({
                    registerDevice:false
                });

        if(
            String(
                context.profile.role || ""
            ).toLowerCase() !== "owner"
        ){
            throw new Error(
                "Manajemen akun cloud hanya untuk Owner."
            );
        }

        return context;
    }

    async function listAccounts(){
        await ownerContext();

        const supabase = client();
        const {data,error} =
            await supabase.rpc(
                "ldm_account_list"
            );

        if(error){
            throw error;
        }

        return Array.isArray(data)
            ? data
            : [];
    }

    async function health(){
        await ownerContext();

        const supabase = client();
        const {data,error} =
            await supabase.rpc(
                "ldm_account_health"
            );

        if(error){
            throw error;
        }

        return data || {};
    }

    async function linkExistingAuth({
        email,
        username,
        displayName,
        role
    }){
        await ownerContext();

        const supabase = client();
        const {data,error} =
            await supabase.rpc(
                "ldm_account_link_existing_auth",
                {
                    p_email:
                        String(email || "")
                            .trim()
                            .toLowerCase(),
                    p_username:
                        String(username || "")
                            .trim(),
                    p_display_name:
                        String(displayName || "")
                            .trim() || null,
                    p_role:
                        String(role || "kasir")
                            .trim()
                            .toLowerCase()
                }
            );

        if(error){
            throw error;
        }

        window.dispatchEvent(
            new CustomEvent(
                "ldm-cloud-accounts-updated"
            )
        );

        return data;
    }

    async function updateProfile({
        userId,
        username,
        displayName,
        role,
        active
    }){
        const context =
            await ownerContext();

        const supabase = client();
        const {data,error} =
            await supabase.rpc(
                "ldm_account_update_profile",
                {
                    p_user_id:userId,
                    p_username:
                        String(username || "")
                            .trim(),
                    p_display_name:
                        String(displayName || "")
                            .trim() || null,
                    p_role:
                        String(role || "kasir")
                            .trim()
                            .toLowerCase(),
                    p_active:
                        Boolean(active)
                }
            );

        if(error){
            throw error;
        }

        if(
            context.user &&
            context.user.id === userId
        ){
            await window.LDMCloudSession
                .ensureAuthenticated({
                    registerDevice:false
                });
        }

        localStorage.removeItem(
            "ldmAttendanceProfiles"
        );

        window.dispatchEvent(
            new CustomEvent(
                "ldm-cloud-accounts-updated"
            )
        );

        return data;
    }

    async function changeOwnPassword(
        newPassword
    ){
        const password =
            String(newPassword || "");

        if(password.length < 8){
            throw new Error(
                "Password baru minimal 8 karakter."
            );
        }

        const supabase = client();
        const {data,error} =
            await supabase.auth.updateUser({
                password
            });

        if(error){
            throw error;
        }

        return data;
    }

    function recoveryRedirectURL(){
        return new URL(
            "account-password-reset.html",
            window.location.href
        ).href;
    }

    async function sendPasswordReset(
        email
    ){
        const normalized =
            String(email || "")
                .trim()
                .toLowerCase();

        if(!normalized){
            throw new Error(
                "Email wajib diisi."
            );
        }

        const supabase = client();
        const {data,error} =
            await supabase.auth
                .resetPasswordForEmail(
                    normalized,
                    {
                        redirectTo:
                            recoveryRedirectURL()
                    }
                );

        if(error){
            throw error;
        }

        return data;
    }

    async function startRealtime(callback){
        if(channel){
            return channel;
        }

        const context =
            await ownerContext();

        const storeId =
            context.profile.store_id;

        const supabase = client();

        channel = supabase
            .channel(CHANNEL_NAME)
            .on(
                "postgres_changes",
                {
                    event:"*",
                    schema:"public",
                    table:"profiles",
                    filter:`store_id=eq.${storeId}`
                },
                payload => {
                    if(
                        typeof callback ===
                            "function"
                    ){
                        callback(payload);
                    }
                }
            )
            .subscribe();

        return channel;
    }

    async function stopRealtime(){
        if(!channel){
            return;
        }

        const supabase = client();
        try{
            await supabase.removeChannel(
                channel
            );
        }finally{
            channel = null;
        }
    }

    window.LDMAccounts =
        Object.freeze({
            ownerContext,
            listAccounts,
            health,
            linkExistingAuth,
            updateProfile,
            changeOwnPassword,
            sendPasswordReset,
            recoveryRedirectURL,
            startRealtime,
            stopRealtime
        });
})();
