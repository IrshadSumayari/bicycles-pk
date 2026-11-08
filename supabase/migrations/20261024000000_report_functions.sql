-- Ledger reports. All period activity uses inclusive Asia/Karachi dates;
-- current inventory and open tailoring work deliberately ignore the period.
CREATE OR REPLACE FUNCTION public.report_tz()
RETURNS TEXT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$ SELECT 'Asia/Karachi'::text $$;
REVOKE ALL ON FUNCTION public.report_tz() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.report_tz() TO authenticated;

-- sales(branch_id, created_at) and the sale_lines(sale_id, line_no) unique
-- index already cover the other requested access paths.
CREATE INDEX IF NOT EXISTS idx_payments_created_at ON public.payments(created_at);
CREATE INDEX IF NOT EXISTS idx_return_lines_return ON public.return_lines(return_id);

CREATE OR REPLACE FUNCTION public.report_sales_summary(
    p_from DATE, p_to DATE, p_branch UUID DEFAULT NULL)
RETURNS TABLE(day DATE, invoices INT, gross NUMERIC, discounts NUMERIC,
    net_sales NUMERIC, tax NUMERIC, returns NUMERIC, returns_tax NUMERIC,
    net_after_returns NUMERIC, cost NUMERIC, margin NUMERIC)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF NOT public.has_app_role(ARRAY['admin','manager']) THEN
        RAISE EXCEPTION 'Only managers can see reports' USING ERRCODE = '42501';
    END IF;
    RETURN QUERY
    WITH sold AS (
        SELECT (s.created_at AT TIME ZONE public.report_tz())::date AS d,
            count(DISTINCT s.id)::int AS n, sum(l.gross) AS g,
            sum(l.manual_discount + l.promotion_discount) AS discount,
            sum(l.net) AS revenue, sum(l.tax) AS taxes,
            sum(l.quantity * coalesce(l.unit_cost, 0)) AS c
        FROM public.sales s JOIN public.sale_lines l ON l.sale_id = s.id
        -- A fully refunded invoice still contributes its original sale.
        WHERE s.status IN ('completed','credit','refunded')
          AND public.is_branch_member(s.branch_id)
          AND (p_branch IS NULL OR s.branch_id = p_branch)
          AND s.created_at >= (p_from::timestamp AT TIME ZONE public.report_tz())
          AND s.created_at < ((p_to + 1)::timestamp AT TIME ZONE public.report_tz())
        GROUP BY 1
    ), refunded AS (
        SELECT (r.created_at AT TIME ZONE public.report_tz())::date AS d,
            sum(l.refund_amount - l.tax_amount) AS revenue, sum(l.tax_amount) AS taxes,
            sum(CASE WHEN l.restocked THEN l.quantity * coalesce(sl.unit_cost, 0) ELSE 0 END) AS c
        FROM public.returns r JOIN public.return_lines l ON l.return_id = r.id
        JOIN public.sale_lines sl ON sl.id = l.sale_line_id
        JOIN public.sales s ON s.id = r.sale_id
        WHERE s.status IN ('completed','credit','refunded')
          AND public.is_branch_member(r.branch_id)
          AND (p_branch IS NULL OR r.branch_id = p_branch)
          AND r.created_at >= (p_from::timestamp AT TIME ZONE public.report_tz())
          AND r.created_at < ((p_to + 1)::timestamp AT TIME ZONE public.report_tz())
        GROUP BY 1
    )
    SELECT coalesce(s.d, r.d), coalesce(s.n, 0), coalesce(s.g, 0), coalesce(s.discount, 0),
        coalesce(s.revenue, 0), coalesce(s.taxes, 0), coalesce(r.revenue, 0), coalesce(r.taxes, 0),
        coalesce(s.revenue, 0) - coalesce(r.revenue, 0), coalesce(s.c, 0) - coalesce(r.c, 0),
        coalesce(s.revenue, 0) - coalesce(r.revenue, 0) - coalesce(s.c, 0) + coalesce(r.c, 0)
    FROM sold s FULL JOIN refunded r ON r.d = s.d ORDER BY 1;
END;
$$;

CREATE OR REPLACE FUNCTION public.report_tenders(
    p_from DATE, p_to DATE, p_branch UUID DEFAULT NULL)
RETURNS TABLE(method TEXT, money_in NUMERIC, money_out NUMERIC, net NUMERIC, count INT)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF NOT public.has_app_role(ARRAY['admin','manager']) THEN
        RAISE EXCEPTION 'Only managers can see reports' USING ERRCODE = '42501';
    END IF;
    RETURN QUERY
    WITH receipts AS (
        -- amount is already net of change (tendered - change_given) for cash.
        SELECT p.method, p.direction, p.amount
        FROM public.payments p
        LEFT JOIN public.sales s ON s.id = p.sale_id
        LEFT JOIN public.returns r ON r.id = p.return_id
        LEFT JOIN public.tailoring_orders o ON o.id = p.tailoring_order_id
        LEFT JOIN public.cash_sessions cs ON cs.id = p.cash_session_id
        WHERE p.method <> 'exchange' AND (s.id IS NULL OR s.status <> 'draft')
          AND public.is_branch_member(coalesce(r.branch_id, s.branch_id, o.branch_id, cs.branch_id))
          AND (p_branch IS NULL OR coalesce(r.branch_id, s.branch_id, o.branch_id, cs.branch_id) = p_branch)
          AND p.created_at >= (p_from::timestamp AT TIME ZONE public.report_tz())
          AND p.created_at < ((p_to + 1)::timestamp AT TIME ZONE public.report_tz())
    )
    SELECT r.method, coalesce(sum(r.amount) FILTER (WHERE r.direction = 'in'), 0),
        coalesce(sum(r.amount) FILTER (WHERE r.direction = 'out'), 0),
        sum(CASE WHEN r.direction = 'out' THEN -r.amount ELSE r.amount END), count(*)::int
    FROM receipts r GROUP BY r.method ORDER BY r.method;
END;
$$;

-- Internal line activity, shared by item demand, the matrix, and staff sales.
-- Never callable by clients: public wrappers check role before reading it.
CREATE OR REPLACE FUNCTION public.report_line_activity(p_from DATE, p_to DATE, p_branch UUID)
RETURNS TABLE(variant_id UUID, sale_id UUID, quantity NUMERIC, net NUMERIC,
    cost NUMERIC, returns NUMERIC, discounts NUMERIC, is_return BOOLEAN)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT l.variant_id, s.id, l.quantity, l.net,
        l.quantity * coalesce(l.unit_cost, 0), 0::numeric,
        l.manual_discount + l.promotion_discount, false
    FROM public.sales s JOIN public.sale_lines l ON l.sale_id = s.id
    WHERE s.status IN ('completed','credit','refunded')
      AND public.is_branch_member(s.branch_id) AND (p_branch IS NULL OR s.branch_id = p_branch)
      AND s.created_at >= (p_from::timestamp AT TIME ZONE public.report_tz())
      AND s.created_at < ((p_to + 1)::timestamp AT TIME ZONE public.report_tz())
    UNION ALL
    SELECT l.variant_id, r.sale_id, -l.quantity, -(l.refund_amount - l.tax_amount),
        CASE WHEN l.restocked THEN -l.quantity * coalesce(sl.unit_cost, 0) ELSE 0 END,
        l.refund_amount - l.tax_amount, 0::numeric, true
    FROM public.returns r JOIN public.return_lines l ON l.return_id = r.id
    JOIN public.sale_lines sl ON sl.id = l.sale_line_id
    JOIN public.sales s ON s.id = r.sale_id
    WHERE s.status IN ('completed','credit','refunded')
      AND public.is_branch_member(r.branch_id) AND (p_branch IS NULL OR r.branch_id = p_branch)
      AND r.created_at >= (p_from::timestamp AT TIME ZONE public.report_tz())
      AND r.created_at < ((p_to + 1)::timestamp AT TIME ZONE public.report_tz())
$$;
REVOKE ALL ON FUNCTION public.report_line_activity(DATE, DATE, UUID) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.report_top_items(
    p_from DATE, p_to DATE, p_branch UUID DEFAULT NULL, p_group TEXT DEFAULT 'style', p_limit INT DEFAULT 50)
RETURNS TABLE(key TEXT, label TEXT, quantity NUMERIC, net NUMERIC, cost NUMERIC, margin NUMERIC)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF NOT public.has_app_role(ARRAY['admin','manager']) THEN
        RAISE EXCEPTION 'Only managers can see reports' USING ERRCODE = '42501';
    END IF;
    IF p_group IS NULL OR p_group NOT IN ('style','variant','category','size','color') THEN
        RAISE EXCEPTION 'Choose style, variant, category, size or color' USING ERRCODE = '22023';
    END IF;
    IF p_limit IS NULL OR p_limit < 1 THEN
        RAISE EXCEPTION 'Choose a positive report limit' USING ERRCODE = '22023';
    END IF;
    RETURN QUERY
    WITH grouped AS (
        SELECT CASE p_group WHEN 'style' THEN st.id::text WHEN 'variant' THEN v.id::text
            WHEN 'category' THEN c.id::text WHEN 'size' THEN v.size WHEN 'color' THEN v.color END AS k,
            CASE p_group WHEN 'style' THEN st.name WHEN 'variant' THEN v.sku
            WHEN 'category' THEN c.name WHEN 'size' THEN v.size WHEN 'color' THEN v.color END AS lbl,
            a.quantity, a.net, a.cost
        FROM public.report_line_activity(p_from, p_to, p_branch) a
        LEFT JOIN public.product_variants v ON v.id = a.variant_id
        LEFT JOIN public.product_styles st ON st.id = v.style_id
        LEFT JOIN public.categories c ON c.id = st.category_id
    )
    SELECT g.k, coalesce(g.lbl, 'Unspecified'), sum(g.quantity), sum(g.net), sum(g.cost), sum(g.net - g.cost)
    FROM grouped g GROUP BY g.k, g.lbl ORDER BY sum(g.net) DESC, g.k NULLS LAST LIMIT p_limit;
END;
$$;

-- p_style must default too because it follows the optional branch argument.
CREATE OR REPLACE FUNCTION public.report_size_color_matrix(
    p_from DATE, p_to DATE, p_branch UUID DEFAULT NULL, p_style UUID DEFAULT NULL)
RETURNS TABLE(size TEXT, color TEXT, sold NUMERIC, on_hand NUMERIC)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF NOT public.has_app_role(ARRAY['admin','manager']) THEN
        RAISE EXCEPTION 'Only managers can see reports' USING ERRCODE = '42501';
    END IF;
    IF p_style IS NULL THEN
        RAISE EXCEPTION 'Choose a style for the size and color report' USING ERRCODE = '22023';
    END IF;
    RETURN QUERY
    WITH demand AS (
        SELECT a.variant_id, sum(a.quantity) AS qty
        FROM public.report_line_activity(p_from, p_to, p_branch) a GROUP BY a.variant_id
    ), stock AS (
        SELECT b.variant_id, sum(b.on_hand) AS qty FROM public.stock_balances b
        WHERE public.is_branch_member(b.branch_id) AND (p_branch IS NULL OR b.branch_id = p_branch)
        GROUP BY b.variant_id
    )
    SELECT v.size, v.color, sum(coalesce(d.qty, 0)), sum(coalesce(b.qty, 0))
    FROM public.product_variants v LEFT JOIN demand d ON d.variant_id = v.id
    LEFT JOIN stock b ON b.variant_id = v.id
    WHERE v.style_id = p_style AND (d.variant_id IS NOT NULL OR b.variant_id IS NOT NULL)
    GROUP BY v.size, v.color ORDER BY v.size, v.color;
END;
$$;

CREATE OR REPLACE FUNCTION public.report_fabric_usage(
    p_from DATE, p_to DATE, p_branch UUID DEFAULT NULL)
RETURNS TABLE(variant_id UUID, sku TEXT, name TEXT, meters_sold NUMERIC,
    meters_tailoring NUMERIC, meters_waste NUMERIC, meters_on_hand NUMERIC)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF NOT public.has_app_role(ARRAY['admin','manager']) THEN
        RAISE EXCEPTION 'Only managers can see reports' USING ERRCODE = '42501';
    END IF;
    RETURN QUERY
    WITH activity AS (
        SELECT m.variant_id,
            sum(CASE WHEN m.movement_type IN ('sale','return') THEN -m.quantity ELSE 0 END) AS sold,
            sum(CASE WHEN m.movement_type = 'issue' AND m.channel = 'tailoring' THEN -m.quantity ELSE 0 END) AS issued,
            sum(CASE WHEN m.quantity < 0 AND m.movement_type IN ('waste','adjust') THEN -m.quantity ELSE 0 END) AS wasted
        FROM public.stock_movements m
        WHERE public.is_branch_member(m.branch_id) AND (p_branch IS NULL OR m.branch_id = p_branch)
          AND m.created_at >= (p_from::timestamp AT TIME ZONE public.report_tz())
          AND m.created_at < ((p_to + 1)::timestamp AT TIME ZONE public.report_tz())
        GROUP BY m.variant_id
    ), stock AS (
        SELECT b.variant_id, sum(b.on_hand) AS qty FROM public.stock_balances b
        WHERE public.is_branch_member(b.branch_id) AND (p_branch IS NULL OR b.branch_id = p_branch)
        GROUP BY b.variant_id
    )
    SELECT v.id, v.sku, s.name, coalesce(a.sold, 0), coalesce(a.issued, 0), coalesce(a.wasted, 0), coalesce(b.qty, 0)
    FROM public.product_variants v JOIN public.product_styles s ON s.id = v.style_id
    LEFT JOIN activity a ON a.variant_id = v.id LEFT JOIN stock b ON b.variant_id = v.id
    WHERE s.kind = 'fabric' AND (a.variant_id IS NOT NULL OR b.variant_id IS NOT NULL)
    ORDER BY v.sku;
END;
$$;

CREATE OR REPLACE FUNCTION public.report_tailoring(
    p_from DATE, p_to DATE, p_branch UUID DEFAULT NULL)
RETURNS TABLE(orders_taken INT, order_value NUMERIC, deposits NUMERIC, balance_collected NUMERIC,
    delivered_items INT, open_orders INT, open_balance NUMERIC, overdue_items INT)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF NOT public.has_app_role(ARRAY['admin','manager']) THEN
        RAISE EXCEPTION 'Only managers can see reports' USING ERRCODE = '42501';
    END IF;
    RETURN QUERY
    WITH orders AS MATERIALIZED (
        SELECT o.*, public.tailoring_order_totals(o.id) AS totals
        FROM public.tailoring_orders o
        WHERE public.is_branch_member(o.branch_id) AND (p_branch IS NULL OR o.branch_id = p_branch)
    ), receipts AS (
        -- There is no deposit flag: the first incoming transaction timestamp
        -- is the deposit batch (including split tenders); later batches collect balance.
        SELECT p.*, min(p.created_at) FILTER (WHERE p.direction = 'in')
            OVER (PARTITION BY p.tailoring_order_id) AS first_receipt
        FROM public.payments p JOIN orders o ON o.id = p.tailoring_order_id
        WHERE p.method <> 'exchange'
    ), period_orders AS (
        SELECT count(*)::int AS n, coalesce(sum((o.totals->>'total')::numeric), 0) AS value
        FROM orders o WHERE o.status NOT IN ('draft','cancelled')
          AND o.created_at >= (p_from::timestamp AT TIME ZONE public.report_tz())
          AND o.created_at < ((p_to + 1)::timestamp AT TIME ZONE public.report_tz())
    ), period_payments AS (
        SELECT coalesce(sum(p.amount) FILTER (WHERE p.direction = 'in' AND p.created_at = p.first_receipt), 0) AS deposit,
            coalesce(sum(p.amount) FILTER (WHERE p.direction = 'in' AND p.created_at > p.first_receipt), 0) AS balance
        FROM receipts p
        WHERE p.created_at >= (p_from::timestamp AT TIME ZONE public.report_tz())
          AND p.created_at < ((p_to + 1)::timestamp AT TIME ZONE public.report_tz())
    ), current_orders AS (
        SELECT count(*)::int AS n, coalesce(sum((o.totals->>'balance')::numeric), 0) AS balance
        FROM orders o WHERE o.status NOT IN ('draft','cancelled','delivered')
    ), items AS (
        SELECT count(*) FILTER (WHERE i.status = 'delivered'
            AND i.delivered_at >= (p_from::timestamp AT TIME ZONE public.report_tz())
            AND i.delivered_at < ((p_to + 1)::timestamp AT TIME ZONE public.report_tz()))::int AS delivered,
            count(*) FILTER (WHERE i.status NOT IN ('delivered','cancelled')
                AND o.status NOT IN ('draft','cancelled','delivered')
                AND o.promised_date < (now() AT TIME ZONE public.report_tz())::date)::int AS overdue
        FROM orders o JOIN public.tailoring_items i ON i.order_id = o.id
    )
    SELECT o.n, o.value, p.deposit, p.balance, i.delivered, c.n, c.balance, i.overdue
    FROM period_orders o CROSS JOIN period_payments p CROSS JOIN current_orders c CROSS JOIN items i;
END;
$$;

CREATE OR REPLACE FUNCTION public.report_staff_sales(
    p_from DATE, p_to DATE, p_branch UUID DEFAULT NULL)
RETURNS TABLE(user_id UUID, name TEXT, invoices INT, net_sales NUMERIC, returns NUMERIC, discounts NUMERIC)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF NOT public.has_app_role(ARRAY['admin','manager']) THEN
        RAISE EXCEPTION 'Only managers can see reports' USING ERRCODE = '42501';
    END IF;
    RETURN QUERY
    SELECT s.cashier_id, coalesce(u.name, 'Unknown'),
        count(DISTINCT a.sale_id) FILTER (WHERE NOT a.is_return)::int,
        coalesce(sum(a.net) FILTER (WHERE NOT a.is_return), 0), sum(a.returns), sum(a.discounts)
    FROM public.report_line_activity(p_from, p_to, p_branch) a
    JOIN public.sales s ON s.id = a.sale_id LEFT JOIN public.users u ON u.id = s.cashier_id
    GROUP BY s.cashier_id, u.name ORDER BY sum(a.net) DESC, s.cashier_id;
END;
$$;

REVOKE ALL ON FUNCTION public.report_sales_summary(DATE, DATE, UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.report_tenders(DATE, DATE, UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.report_top_items(DATE, DATE, UUID, TEXT, INT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.report_size_color_matrix(DATE, DATE, UUID, UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.report_fabric_usage(DATE, DATE, UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.report_tailoring(DATE, DATE, UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.report_staff_sales(DATE, DATE, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.report_sales_summary(DATE, DATE, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.report_tenders(DATE, DATE, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.report_top_items(DATE, DATE, UUID, TEXT, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.report_size_color_matrix(DATE, DATE, UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.report_fabric_usage(DATE, DATE, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.report_tailoring(DATE, DATE, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.report_staff_sales(DATE, DATE, UUID) TO authenticated;
