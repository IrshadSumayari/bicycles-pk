-- =====================================================================
-- Remove the legacy product model
--   * process_sale() is replaced by post_sale()
--   * products / product_batches are replaced by product_styles /
--     product_variants and the stock ledger (data was copied earlier)
--   * product_variants.legacy_product_id is kept, without the foreign key,
--     so old promotions that name legacy product ids keep matching
-- =====================================================================

DROP FUNCTION IF EXISTS public.process_sale(JSONB);

ALTER TABLE public.product_variants DROP CONSTRAINT IF EXISTS product_variants_legacy_product_id_fkey;

DROP TABLE IF EXISTS public.product_batches;
DROP TABLE IF EXISTS public.products;
