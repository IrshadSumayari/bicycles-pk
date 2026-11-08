-- Lets checkout remove an automatic promotion from one sale.
--
-- quote_sale() reads an optional "skipped_promotions" array of discount ids and
-- leaves those promotions out. post_sale() prices through quote_sale() with the
-- same request, so the charged total matches what the checkout screen showed.
-- Skipping a promotion only raises the price, so any counter role may do it.
-- Discount codes are not affected: the cashier removes a code by not sending it.
-- Patched in place (like 20261103000000) so earlier LadyVogue changes stay.

CREATE OR REPLACE FUNCTION pg_temp.patch_function(p_function regprocedure, p_pairs text[])
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_def text := replace(pg_get_functiondef(p_function), chr(13), ''); i int;
BEGIN
  FOR i IN 1 .. array_length(p_pairs, 1) / 2 LOOP
    IF position(p_pairs[2 * i - 1] IN v_def) = 0 THEN
      RAISE EXCEPTION '% changed; fragment % not found', p_function, i;
    END IF;
    v_def := replace(v_def, p_pairs[2 * i - 1], p_pairs[2 * i]);
  END LOOP;
  EXECUTE v_def;
END $$;

SELECT pg_temp.patch_function('public.quote_sale(jsonb)', ARRAY[
  '    v_code public.discount_codes;' || chr(10) || 'BEGIN',
  $p$    v_code public.discount_codes;
    -- Automatic promotions the cashier removed from this sale
    v_skip TEXT[] := CASE WHEN jsonb_typeof(p_request->'skipped_promotions') = 'array'
        THEN ARRAY(SELECT jsonb_array_elements_text(p_request->'skipped_promotions'))
        ELSE ARRAY[]::TEXT[] END;
BEGIN$p$,
  '        WHERE active AND now() BETWEEN valid_from AND valid_to' || chr(10),
  '        WHERE active AND now() BETWEEN valid_from AND valid_to' || chr(10)
    || '          AND NOT (id::text = ANY(v_skip))' || chr(10)]);

REVOKE ALL ON FUNCTION public.quote_sale(JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.quote_sale(JSONB) TO authenticated;
