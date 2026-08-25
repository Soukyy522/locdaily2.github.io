(function(){
    "use strict";

    const REALTIME_CHANNEL =
        "ldm-transactions-realtime-v8";

    let channel = null;

    function client(){
        if(
            !window.LDMSupabase ||
            typeof window.LDMSupabase.createClient !==
                "function"
        ){
            throw new Error(
                "Supabase client belum tersedia."
            );
        }

        return window.LDMSupabase
            .createClient();
    }

    function createUUID(){
        if(
            window.crypto &&
            typeof window.crypto.randomUUID ===
                "function"
        ){
            return window.crypto.randomUUID();
        }

        const bytes = new Uint8Array(16);
        window.crypto.getRandomValues(bytes);

        bytes[6] =
            (bytes[6] & 0x0f) | 0x40;
        bytes[8] =
            (bytes[8] & 0x3f) | 0x80;

        const hex = Array
            .from(bytes)
            .map(
                b => b
                    .toString(16)
                    .padStart(2, "0")
            )
            .join("");

        return [
            hex.slice(0,8),
            hex.slice(8,12),
            hex.slice(12,16),
            hex.slice(16,20),
            hex.slice(20)
        ].join("-");
    }

    function number(value, fallback = 0){
        const n = Number(value);
        return Number.isFinite(n)
            ? n
            : fallback;
    }

    function resolveProductId(item){
        if(item && item.productId){
            return item.productId;
        }

        if(item && item.id){
            return item.id;
        }

        let cache = [];

        try{
            const parsed = JSON.parse(
                localStorage.getItem(
                    "dataBarang"
                ) || "[]"
            );

            cache = Array.isArray(parsed)
                ? parsed
                : [];
        }catch(error){
            cache = [];
        }

        const barcode = String(
            item && item.barcode || ""
        ).trim();

        const name = String(
            item && item.nama || ""
        )
            .trim()
            .toLowerCase();

        const product = cache.find(
            row =>
                (
                    barcode &&
                    String(row.barcode || "").trim() ===
                        barcode
                )
                ||
                (
                    name &&
                    String(row.nama || "")
                        .trim()
                        .toLowerCase() ===
                        name
                )
        );

        return product && product.id
            ? product.id
            : null;
    }

    function buildItems(cart){
        if(!Array.isArray(cart)){
            return [];
        }

        return cart.map(
            item => {
                const productId =
                    resolveProductId(item);

                if(!productId){
                    throw new Error(
                        `Barang ${item && item.nama ? item.nama : "-"} belum memiliki UUID cloud. Jalankan migrasi Master Barang Tahap 7.`
                    );
                }

                const qty = number(
                    item.qty,
                    0
                );

                if(qty <= 0){
                    throw new Error(
                        "Qty transaksi tidak valid."
                    );
                }

                return {
                    product_id:
                        productId,
                    qty:
                        qty
                };
            }
        );
    }

    async function checkout(options){
        if(!options){
            throw new Error(
                "Payload checkout kosong."
            );
        }

        if(!window.LDMCloudSession){
            throw new Error(
                "Cloud Session belum tersedia."
            );
        }

        await window.LDMCloudSession
            .ensureAuthenticated({
                registerDevice:
                    false
            });

        const clientTransactionId =
            options.clientTransactionId ||
            createUUID();

        const items =
            buildItems(
                options.items
            );

        const supabase = client();

        const {
            data,
            error
        } = await supabase.rpc(
            "ldm_complete_sale",
            {
                p_client_transaction_id:
                    clientTransactionId,
                p_items:
                    items,
                p_manual_discount:
                    Math.max(
                        0,
                        number(
                            options.manualDiscount,
                            0
                        )
                    ),
                p_payment_method:
                    options.paymentMethod ||
                    "Tunai",
                p_cash_received:
                    Math.max(
                        0,
                        number(
                            options.cashReceived,
                            0
                        )
                    ),
                p_cash_amount:
                    Math.max(
                        0,
                        number(
                            options.cashAmount,
                            0
                        )
                    ),
                p_qris_amount:
                    Math.max(
                        0,
                        number(
                            options.qrisAmount,
                            0
                        )
                    ),
                p_shift_label:
                    options.shiftLabel ||
                    null
            }
        );

        if(error){
            throw error;
        }

        if(!data || !data.id){
            throw new Error(
                "Supabase tidak mengembalikan transaksi yang valid."
            );
        }

        return data;
    }

    async function recentTransactions(limit = 30){
        const supabase = client();

        const safeLimit = Math.min(
            100,
            Math.max(
                1,
                Number(limit) || 30
            )
        );

        const {
            data,
            error
        } = await supabase
            .from("transactions")
            .select(
                [
                    "id",
                    "client_transaction_id",
                    "transaction_code",
                    "cashier_username",
                    "shift_label",
                    "business_date",
                    "transacted_at",
                    "payment_method",
                    "normal_subtotal",
                    "subtotal",
                    "product_discount",
                    "manual_discount",
                    "total_discount",
                    "grand_total",
                    "cash_received",
                    "cash_amount",
                    "qris_amount",
                    "change_amount",
                    "status"
                ].join(",")
            )
            .order(
                "transacted_at",
                {
                    ascending:
                        false
                }
            )
            .limit(safeLimit);

        if(error){
            throw error;
        }

        return Array.isArray(data)
            ? data
            : [];
    }

    async function recentMovements(limit = 50){
        const supabase = client();

        const safeLimit = Math.min(
            200,
            Math.max(
                1,
                Number(limit) || 50
            )
        );

        const {
            data,
            error
        } = await supabase
            .from("stock_movements")
            .select(
                [
                    "id",
                    "product_id",
                    "transaction_id",
                    "movement_type",
                    "quantity_change",
                    "stock_before",
                    "stock_after",
                    "reference_code",
                    "occurred_at"
                ].join(",")
            )
            .order(
                "occurred_at",
                {
                    ascending:
                        false
                }
            )
            .limit(safeLimit);

        if(error){
            throw error;
        }

        return Array.isArray(data)
            ? data
            : [];
    }

    async function voidSale(
        transactionId,
        reason = "Void transaksi"
    ){
        const supabase = client();

        const {
            data,
            error
        } = await supabase.rpc(
            "ldm_void_sale",
            {
                p_transaction_id:
                    transactionId,
                p_reason:
                    reason
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

        if(!window.LDMCloudSession){
            throw new Error(
                "Cloud Session belum tersedia."
            );
        }

        const context =
            await window.LDMCloudSession
                .ensureAuthenticated({
                    registerDevice:
                        false
                });

        const storeId =
            context.profile.store_id;

        const supabase = client();

        channel = supabase
            .channel(
                REALTIME_CHANNEL
            )
            .on(
                "postgres_changes",
                {
                    event: "*",
                    schema: "public",
                    table: "transactions",
                    filter:
                        `store_id=eq.${storeId}`
                },
                payload => {
                    if(
                        typeof callback ===
                        "function"
                    ){
                        callback(
                            "transactions",
                            payload
                        );
                    }
                }
            )
            .on(
                "postgres_changes",
                {
                    event: "*",
                    schema: "public",
                    table: "stock_movements",
                    filter:
                        `store_id=eq.${storeId}`
                },
                payload => {
                    if(
                        typeof callback ===
                        "function"
                    ){
                        callback(
                            "stock_movements",
                            payload
                        );
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

    window.LDMTransactions =
        Object.freeze({
            createUUID,
            buildItems,
            checkout,
            recentTransactions,
            recentMovements,
            voidSale,
            startRealtime,
            stopRealtime
        });
})();
