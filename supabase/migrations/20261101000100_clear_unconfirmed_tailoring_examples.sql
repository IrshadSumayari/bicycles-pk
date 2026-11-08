-- The original garment forms included example prices, delivery days and fabric
-- estimates. Keep useful measurement forms, but do not offer unused, unconfirmed
-- examples as real shop quotes. Never change used or explicitly saved settings.
WITH presets(code,charge,days,meters) AS (VALUES
 ('SHALWAR_KAMEEZ',2500::numeric,7,4.5::numeric),('KURTA',1800,5,2.75),
 ('SHERWANI',12000,14,3.5),('SUIT_COAT',9000,14,2),('WAISTCOAT',3500,7,1.2),
 ('TROUSERS',2000,5,1.3),('SHIRT',1500,5,2),('ALTERATION',500,2,NULL::numeric)
), original AS (
 SELECT g.code,to_jsonb(g.*) old_value FROM public.garment_types g JOIN presets p ON p.code=g.code
 WHERE g.active AND g.default_charge=p.charge AND g.lead_days=p.days AND g.fabric_meters IS NOT DISTINCT FROM p.meters
 AND NOT EXISTS(SELECT 1 FROM public.measurement_sets WHERE garment_type=g.code)
 AND NOT EXISTS(SELECT 1 FROM public.tailoring_items WHERE garment_type=g.code)
 AND NOT EXISTS(SELECT 1 FROM public.tailoring_requests WHERE garment_type=g.code)
 AND NOT EXISTS(SELECT 1 FROM public.idempotency_keys WHERE operation='save_garment_type' AND result->>'code'=g.code)
 AND NOT EXISTS(SELECT 1 FROM public.lookup_events WHERE kind='garment_type' AND lookup_id=g.code)
), changed AS (
 UPDATE public.garment_types g SET default_charge=0,lead_days=0,fabric_meters=NULL,active=false
 FROM original o WHERE o.code=g.code RETURNING g.code,o.old_value,to_jsonb(g.*) new_value
)
INSERT INTO public.lookup_events(kind,lookup_id,action,old_value,new_value)
SELECT 'garment_type',code,'save',old_value,new_value FROM changed;
