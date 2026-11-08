-- Contact capture and consent-based campaign preparation. No message delivery.
ALTER TABLE public.customers
  ADD COLUMN email_marketing_consent boolean,
  ADD COLUMN sms_marketing_consent boolean,
  ADD COLUMN email_consent_at timestamptz,
  ADD COLUMN sms_consent_at timestamptz;
ALTER TABLE public.customer_accounts
  ADD COLUMN email_marketing_consent boolean,
  ADD COLUMN sms_marketing_consent boolean,
  ADD COLUMN email_consent_at timestamptz,
  ADD COLUMN sms_consent_at timestamptz;
-- NULL means not asked. Do not interpret historical general consent as channel consent.
CREATE TABLE public.marketing_consent_events (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  subject_id uuid NOT NULL,
  source text NOT NULL CHECK (source IN ('customers','customer_accounts')),
  channel text NOT NULL CHECK (channel IN ('email','sms')),
  contact text,
  consent boolean,
  recorded_by uuid DEFAULT auth.uid(),
  recorded_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.marketing_consent_events ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.marketing_consent_events TO authenticated;
CREATE POLICY marketing_events_read ON public.marketing_consent_events FOR SELECT TO authenticated
  USING (public.has_app_role(ARRAY['admin','manager']));
REVOKE INSERT, UPDATE, DELETE ON public.marketing_consent_events FROM anon, authenticated;

CREATE FUNCTION public.record_marketing_consent() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE email_changed boolean; sms_changed boolean;
BEGIN
  IF TG_OP='UPDATE' THEN
    -- A new address/phone needs its own consent, even if a caller resubmits true.
    IF lower(trim(coalesce(NEW.email,''))) IS DISTINCT FROM lower(trim(coalesce(OLD.email,''))) THEN
      NEW.email_marketing_consent := NULL;
    END IF;
    IF public.normalize_phone(NEW.phone) IS DISTINCT FROM public.normalize_phone(OLD.phone) THEN
      NEW.sms_marketing_consent := NULL;
    END IF;
    email_changed := NEW.email_marketing_consent IS DISTINCT FROM OLD.email_marketing_consent
      OR lower(trim(coalesce(NEW.email,''))) IS DISTINCT FROM lower(trim(coalesce(OLD.email,'')));
    sms_changed := NEW.sms_marketing_consent IS DISTINCT FROM OLD.sms_marketing_consent
      OR public.normalize_phone(NEW.phone) IS DISTINCT FROM public.normalize_phone(OLD.phone);
    NEW.email_consent_at := OLD.email_consent_at;
    NEW.sms_consent_at := OLD.sms_consent_at;
  ELSE
    email_changed := NEW.email_marketing_consent IS NOT NULL;
    sms_changed := NEW.sms_marketing_consent IS NOT NULL;
    NEW.email_consent_at := NULL;
    NEW.sms_consent_at := NULL;
  END IF;
  IF NEW.email_marketing_consent IS TRUE AND coalesce(trim(NEW.email),'') !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' THEN
    RAISE EXCEPTION 'A valid email is required for email offers';
  END IF;
  IF NEW.sms_marketing_consent IS TRUE AND coalesce(public.normalize_phone(NEW.phone),'') !~ '^\+[1-9][0-9]{7,14}$' THEN
    RAISE EXCEPTION 'A valid international phone number is required for SMS offers';
  END IF;
  IF email_changed THEN
    NEW.email_consent_at := CASE WHEN NEW.email_marketing_consent IS NULL THEN NULL ELSE now() END;
    INSERT INTO marketing_consent_events(subject_id,source,channel,contact,consent)
      VALUES(NEW.id,TG_TABLE_NAME,'email',lower(trim(NEW.email)),NEW.email_marketing_consent);
  END IF;
  IF sms_changed THEN
    NEW.sms_consent_at := CASE WHEN NEW.sms_marketing_consent IS NULL THEN NULL ELSE now() END;
    INSERT INTO marketing_consent_events(subject_id,source,channel,contact,consent)
      VALUES(NEW.id,TG_TABLE_NAME,'sms',public.normalize_phone(NEW.phone),NEW.sms_marketing_consent);
  END IF;
  RETURN NEW;
END; $$;
REVOKE ALL ON FUNCTION public.record_marketing_consent() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER customers_marketing_consent BEFORE INSERT OR UPDATE ON public.customers
  FOR EACH ROW EXECUTE FUNCTION public.record_marketing_consent();
CREATE TRIGGER accounts_marketing_consent BEFORE INSERT OR UPDATE ON public.customer_accounts
  FOR EACH ROW EXECUTE FUNCTION public.record_marketing_consent();

CREATE TABLE public.marketing_campaigns (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL CHECK (length(trim(name)) BETWEEN 1 AND 150),
  channel text NOT NULL CHECK(channel IN ('email','sms')),
  subject text NOT NULL DEFAULT '' CHECK(length(subject)<=200),
  body text NOT NULL CHECK(length(trim(body)) BETWEEN 1 AND 10000),
  status text NOT NULL DEFAULT 'draft' CHECK(status='draft'),
  created_by uuid NOT NULL DEFAULT auth.uid(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.marketing_campaigns ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.marketing_campaigns TO authenticated;
CREATE POLICY campaigns_select ON public.marketing_campaigns FOR SELECT TO authenticated
  USING(public.has_app_role(ARRAY['admin','manager']));
CREATE POLICY campaigns_insert ON public.marketing_campaigns FOR INSERT TO authenticated
  WITH CHECK(public.has_app_role(ARRAY['admin','manager']) AND created_by=auth.uid());
CREATE POLICY campaigns_update ON public.marketing_campaigns FOR UPDATE TO authenticated
  USING(public.has_app_role(ARRAY['admin','manager'])) WITH CHECK(public.has_app_role(ARRAY['admin','manager']));
CREATE POLICY campaigns_delete ON public.marketing_campaigns FOR DELETE TO authenticated
  USING(public.has_app_role(ARRAY['admin','manager']));
CREATE TRIGGER campaigns_updated BEFORE UPDATE ON public.marketing_campaigns
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE FUNCTION public.marketing_audience(p_channel text,p_query text DEFAULT '',p_limit int DEFAULT 50,p_offset int DEFAULT 0)
RETURNS TABLE(name text,contact text,source text,consent_at timestamptz,total_count bigint)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF NOT public.has_app_role(ARRAY['admin','manager']) THEN
    RAISE EXCEPTION 'Marketing audiences are for managers only' USING ERRCODE='42501';
  END IF;
  IF p_channel NOT IN ('email','sms') OR p_channel IS NULL THEN RAISE EXCEPTION 'Choose email or SMS'; END IF;
  RETURN QUERY
  WITH contacts AS (
    SELECT c.name AS person,
      CASE WHEN p_channel='email' THEN lower(trim(c.email)) ELSE public.normalize_phone(c.phone) END AS destination,
      CASE WHEN p_channel='email' THEN c.email_marketing_consent ELSE c.sms_marketing_consent END AS opted,
      CASE WHEN p_channel='email' THEN c.email_consent_at ELSE c.sms_consent_at END AS consent_time,
      'POS'::text AS origin FROM public.customers c
    UNION ALL
    SELECT a.full_name,
      CASE WHEN p_channel='email' THEN lower(trim(a.email)) ELSE public.normalize_phone(a.phone) END,
      CASE WHEN p_channel='email' THEN a.email_marketing_consent ELSE a.sms_marketing_consent END,
      CASE WHEN p_channel='email' THEN a.email_consent_at ELSE a.sms_consent_at END,
      'Website'::text FROM public.customer_accounts a
  ), eligible AS (
    SELECT min(coalesce(c.person,'')) AS person,c.destination,string_agg(DISTINCT c.origin,' + ' ORDER BY c.origin) AS origin,max(c.consent_time) AS consent_time
    FROM contacts c
    WHERE c.opted IS NOT NULL AND CASE WHEN p_channel='email'
      THEN c.destination ~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
      ELSE c.destination ~ '^\+[1-9][0-9]{7,14}$' END
    GROUP BY c.destination HAVING bool_and(c.opted)
  )
  SELECT e.person,e.destination,e.origin,e.consent_time,count(*) OVER()
  FROM eligible e
  WHERE coalesce(p_query,'')='' OR position(lower(p_query) IN lower(e.person||' '||e.destination))>0
  ORDER BY e.destination LIMIT least(greatest(coalesce(p_limit,50),1),1000) OFFSET greatest(coalesce(p_offset,0),0);
END; $$;
REVOKE ALL ON FUNCTION public.marketing_audience(text,text,int,int) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.marketing_audience(text,text,int,int) TO authenticated;
