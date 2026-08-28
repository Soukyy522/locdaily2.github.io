-- ================================================================
-- Verifikasi Histori Harga Beli + Snapshot HPP
-- Jalankan setelah 17-stage20-historical-purchase-price-profit.sql
-- ================================================================

select
    to_regclass('public.product_purchase_price_history') is not null
        as history_table_ready,
    exists(
        select 1 from pg_trigger
        where tgname='trg_products_purchase_price_history'
          and not tgisinternal
    ) as product_history_trigger_ready,
    exists(
        select 1 from pg_trigger
        where tgname='trg_transaction_items_historical_cost'
          and not tgisinternal
    ) as transaction_cost_trigger_ready,
    exists(
        select 1 from pg_trigger
        where tgname='trg_stock_movements_historical_sale_cost'
          and not tgisinternal
    ) as stock_cost_trigger_ready;

-- Semua produk aktif seharusnya sudah mempunyai setidaknya satu histori harga.
select
    count(*) filter(where h.product_id is null) as products_without_price_history,
    count(*) as active_products_checked
from public.products p
left join lateral (
    select ph.product_id
    from public.product_purchase_price_history ph
    where ph.store_id=p.store_id
      and ph.product_id=p.id
    limit 1
) h on true
where p.deleted_at is null;

-- Audit snapshot transaksi terbaru. cost_price_snapshot adalah nilai yang akan
-- dipakai laporan untuk menghitung HPP dan profit tanpa membaca harga terbaru.
select
    t.transaction_code,
    t.transacted_at,
    ti.product_name_snapshot,
    ti.qty,
    ti.cost_price_snapshot,
    ti.unit_price,
    ti.line_subtotal,
    round(ti.line_subtotal-(ti.qty*ti.cost_price_snapshot),2)
        as profit_item_sebelum_diskon_manual
from public.transaction_items ti
join public.transactions t on t.id=ti.transaction_id
where t.store_id=public.ldm_current_store_id()
order by t.transacted_at desc,ti.created_at desc
limit 25;
