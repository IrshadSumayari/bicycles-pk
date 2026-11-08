-- Product search: optional sort, so staff can list recently changed or newly
-- added items first. Without a sort (or with any other value) the existing
-- name order is unchanged, and an exact SKU/barcode match still comes first.
--   {"sort":"updated"} newest edit of the style or variant first
--   {"sort":"newest"}  most recently created variant first

-- Fails loudly if a fragment is missing, so a changed definition is reviewed.
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

SELECT pg_temp.patch_function('public.search_variants(jsonb)', ARRAY[
  '  s.name,v.sku,v.id
 LIMIT v_limit OFFSET v_offset;',
  '  CASE WHEN p->>''sort''=''updated'' THEN greatest(s.updated_at,v.updated_at) END DESC NULLS LAST,
  CASE WHEN p->>''sort''=''newest'' THEN v.created_at END DESC NULLS LAST,
  s.name,v.sku,v.id
 LIMIT v_limit OFFSET v_offset;']);
