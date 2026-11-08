-- Rebrand defaults and legacy settings without changing shop transactions.
ALTER TABLE public.app_settings ALTER COLUMN store_name SET DEFAULT 'LadyVogue POS';

UPDATE public.app_settings
SET store_name = 'LadyVogue POS'
WHERE store_name IS NULL OR btrim(store_name) = '' OR store_name ~* 'nextera';

UPDATE public.app_settings
SET receipt_header = regexp_replace(coalesce(receipt_header, ''), 'nextera(\s+pos)?(\s+(store|system))?', 'LadyVogue POS', 'gi'),
    receipt_footer = regexp_replace(coalesce(receipt_footer, ''), 'nextera(\s+pos)?(\s+(store|system))?', 'LadyVogue POS', 'gi')
WHERE receipt_header ~* 'nextera' OR receipt_footer ~* 'nextera';

UPDATE public.app_settings SET store_email = '' WHERE store_email ~* 'nextera';
