-- Counter search: optional category list, so the POS Jewellery section can
-- show every jewellery category at once instead of one exact category.
-- The existing single `category` filter is unchanged; both can be combined.

-- Fails loudly if a fragment is missing, so a changed definition is reviewed.
-- Line endings are normalised first: a Windows checkout stores CRLF bodies.
-- Replaced, not created: a migration run in one session already defines it.
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
  'AND (nullif(p->>''category'','''') IS NULL OR c.name=p->>''category'')',
  'AND (nullif(p->>''category'','''') IS NULL OR c.name=p->>''category'')
  AND (jsonb_typeof(p->''categories'') IS DISTINCT FROM ''array''
    OR c.name IN (SELECT jsonb_array_elements_text(p->''categories'')))']);
