-- Storefront: optional category list, so a shop section (Bicycles, Kids...)
-- can list every one of its categories at once. The single `category`
-- filter is unchanged; both can be combined.
DO $$ DECLARE def TEXT:=replace(pg_get_functiondef('public.catalog_list(jsonb)'::regprocedure),chr(13),'');
 old TEXT:='AND (nullif(p->>''category'','''') IS NULL OR c.category=p->>''category'')';
BEGIN
 IF position(old IN def)=0 THEN RAISE EXCEPTION 'catalog_list changed; category fragment not found'; END IF;
 EXECUTE replace(def,old,old||'
  AND (jsonb_typeof(p->''categories'') IS DISTINCT FROM ''array''
    OR c.category IN (SELECT jsonb_array_elements_text(p->''categories'')))');
END $$;
