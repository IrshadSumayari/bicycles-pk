-- Related returns/payments have narrower RLS than sales (a refund may have
-- been handled by a different cashier). Definer functions check the sale's
-- role, owner AND branch explicitly before reading its complete ledger.
CREATE OR REPLACE FUNCTION public.search_sales(p JSONB DEFAULT '{}'::jsonb)
RETURNS TABLE(id UUID, invoice_number TEXT, created_at TIMESTAMPTZ, status TEXT,
    customer_id UUID, customer_name TEXT, cashier_name TEXT, total NUMERIC,
    paid_methods TEXT[], returned_amount NUMERIC, line_count INT, total_count BIGINT)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_from DATE := NULLIF(p->>'from', '')::date;
    v_to DATE := NULLIF(p->>'to', '')::date;
    v_status TEXT := NULLIF(p->>'status', '');
    v_method TEXT := NULLIF(p->>'method', '');
    -- Treat search text literally, including %, _ and backslash.
    v_q TEXT := replace(replace(replace(trim(coalesce(p->>'q', '')), E'\\', E'\\\\'), '%', E'\\%'), '_', E'\\_');
    v_phone TEXT := regexp_replace(coalesce(p->>'q', ''), '[^0-9]', '', 'g');
    v_limit INT := least(200, greatest(1, coalesce((p->>'limit')::int, 50)));
    v_offset INT := greatest(0, coalesce((p->>'offset')::int, 0));
BEGIN
    IF NOT public.is_counter_staff() THEN RETURN; END IF;
    IF v_status IS NOT NULL AND v_status NOT IN ('completed','credit','draft','returned','refunded') THEN
        RAISE EXCEPTION 'Choose a valid sale status' USING ERRCODE = '22023';
    END IF;
    IF v_method IS NOT NULL AND v_method NOT IN ('cash','card','digital','credit','exchange') THEN
        RAISE EXCEPTION 'Choose a valid payment method' USING ERRCODE = '22023';
    END IF;
    RETURN QUERY
    SELECT s.id, s.invoice_number, s.created_at, s.status, s.customer_id,
        coalesce(s.customer_name, c.name), coalesce(s.cashier, u.name), s.total,
        ARRAY(SELECT DISTINCT pay.method FROM public.payments pay WHERE pay.sale_id = s.id ORDER BY pay.method),
        coalesce((SELECT sum(r.refund_total) FROM public.returns r WHERE r.sale_id = s.id), 0),
        (SELECT count(*)::int FROM public.sale_lines l WHERE l.sale_id = s.id), count(*) OVER ()
    FROM public.sales s
    LEFT JOIN public.customers c ON c.id = s.customer_id
    LEFT JOIN public.users u ON u.id = s.cashier_id
    WHERE public.is_branch_member(s.branch_id)
      AND (public.has_app_role(ARRAY['admin','manager']) OR s.cashier_id = auth.uid())
      AND (v_from IS NULL OR s.created_at >= (v_from::timestamp AT TIME ZONE public.report_tz()))
      AND (v_to IS NULL OR s.created_at < ((v_to + 1)::timestamp AT TIME ZONE public.report_tz()))
      AND (v_status IS NULL OR s.status = v_status OR (v_status = 'returned' AND EXISTS (
          SELECT 1 FROM public.returns r WHERE r.sale_id = s.id)))
      AND (v_method IS NULL OR EXISTS (SELECT 1 FROM public.payments pay WHERE pay.sale_id = s.id AND pay.method = v_method))
      AND (v_q = '' OR s.invoice_number ILIKE v_q || '%' OR c.name ILIKE '%' || v_q || '%'
          OR s.customer_name ILIKE '%' || v_q || '%' OR c.phone ILIKE '%' || v_q || '%'
          -- Also accept local 03xx and formatted +92 phone searches.
          OR (coalesce(p->>'q', '') ~ '^[+0-9() .-]+$' AND length(v_phone) >= 4 AND (c.phone LIKE '%' || v_phone || '%'
              OR (left(v_phone, 1) = '0' AND c.phone LIKE '%' || substr(v_phone, 2) || '%')))
          OR EXISTS (SELECT 1 FROM public.sale_lines l WHERE l.sale_id = s.id AND l.sku ILIKE '%' || v_q || '%'))
    ORDER BY s.created_at DESC, s.id
    LIMIT v_limit OFFSET v_offset;
END;
$$;

CREATE OR REPLACE FUNCTION public.sale_detail(p_sale_id UUID)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_sale public.sales;
BEGIN
    SELECT s.* INTO v_sale FROM public.sales s
    WHERE s.id = p_sale_id AND public.is_counter_staff() AND public.is_branch_member(s.branch_id)
      AND (public.has_app_role(ARRAY['admin','manager']) OR s.cashier_id = auth.uid());
    IF v_sale.id IS NULL THEN RETURN NULL; END IF;
    RETURN jsonb_build_object(
        'header', jsonb_build_object(
            'id', v_sale.id, 'invoice_number', v_sale.invoice_number, 'receipt_number', v_sale.receipt_number,
            'created_at', v_sale.created_at, 'status', v_sale.status,
            'customer_id', v_sale.customer_id, 'customer_name', coalesce(v_sale.customer_name, (SELECT c.name FROM public.customers c WHERE c.id = v_sale.customer_id)),
            'cashier_name', coalesce(v_sale.cashier, (SELECT u.name FROM public.users u WHERE u.id = v_sale.cashier_id)),
            'subtotal', v_sale.subtotal, 'discount_amount', v_sale.discount_amount, 'tax_amount', v_sale.tax_amount,
            'total', v_sale.total, 'payment_method', v_sale.payment_method, 'notes', v_sale.notes),
        -- Explicit public line fields: unit_cost is intentionally not exposed to cashiers.
        'lines', coalesce((SELECT jsonb_agg(jsonb_build_object(
            'id', l.id, 'line_no', l.line_no, 'variant_id', l.variant_id, 'description', l.description,
            'sku', l.sku, 'unit', l.unit, 'quantity', l.quantity, 'unit_price', l.unit_price,
            'gross', l.gross, 'manual_discount', l.manual_discount, 'promotion_discount', l.promotion_discount,
            'net', l.net, 'taxable', l.taxable, 'tax', l.tax, 'total', l.total, 'is_gift', l.is_gift,
            'returned_quantity', coalesce((SELECT sum(rl.quantity) FROM public.return_lines rl WHERE rl.sale_line_id = l.id), 0)
        ) ORDER BY l.line_no) FROM public.sale_lines l WHERE l.sale_id = v_sale.id), '[]'::jsonb),
        'payments', coalesce((SELECT jsonb_agg(jsonb_build_object(
            'id', pay.id, 'created_at', pay.created_at, 'direction', pay.direction, 'method', pay.method,
            'amount', pay.amount, 'tendered', pay.tendered, 'change_given', pay.change_given,
            'reference', pay.reference, 'card_type', pay.card_type, 'card_last4', pay.card_last4, 'return_id', pay.return_id
        ) ORDER BY pay.created_at, pay.id) FROM public.payments pay
        WHERE pay.sale_id = v_sale.id OR EXISTS (SELECT 1 FROM public.returns r WHERE r.id = pay.return_id AND r.sale_id = v_sale.id)), '[]'::jsonb),
        'returns', coalesce((SELECT jsonb_agg(jsonb_build_object(
            'id', r.id, 'return_no', r.return_no, 'created_at', r.created_at, 'reason', r.reason,
            'refund_total', r.refund_total, 'refund_method', r.refund_method
        ) ORDER BY r.created_at, r.id) FROM public.returns r WHERE r.sale_id = v_sale.id), '[]'::jsonb)
    );
END;
$$;

-- Existing sales(branch_id, created_at), sales(cashier_id), sale_lines(sale_id,
-- line_no), payments(sale_id) and returns(sale_id) indexes cover these joins.
REVOKE ALL ON FUNCTION public.search_sales(JSONB) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.sale_detail(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.search_sales(JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.sale_detail(UUID) TO authenticated;
