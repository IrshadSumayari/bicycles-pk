-- Existing alteration forms can intentionally have no measurements. Let an owner
-- edit their price/status without inventing a measurement field. New measurement
-- types still require a field; all existing role, validation and history rules remain.
DO $patch$
DECLARE definition TEXT; revised TEXT;
BEGIN
 SELECT pg_get_functiondef('public.save_garment_type(jsonb)'::regprocedure) INTO definition;
 revised:=replace(definition,
 $old$IF jsonb_array_length(p->'fields')=0 THEN RAISE EXCEPTION 'Add at least one measurement field'; END IF;$old$,
 $new$IF jsonb_array_length(p->'fields')=0 AND NOT EXISTS (
   SELECT 1 FROM public.garment_types g WHERE g.code=coalesce(nullif(p->>'original_code',''),p->>'code') AND jsonb_array_length(g.fields)=0
 ) THEN RAISE EXCEPTION 'Add at least one measurement field'; END IF;$new$);
 IF revised=definition THEN RAISE EXCEPTION 'Garment editor definition changed; review before applying the measurement-free form upgrade'; END IF;
 EXECUTE revised;
END;
$patch$;
