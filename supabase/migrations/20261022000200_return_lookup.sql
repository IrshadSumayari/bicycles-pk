-- =====================================================================
-- Receipt lookup for returns
-- Cashiers can only list their own sales, but a customer may bring back an
-- item sold by anyone. This returns just what a return needs for one
-- invoice number in the caller's branch.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.find_sale_for_return(p_invoice TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_sale public.sales;
    v_days INTEGER;
BEGIN
    IF public.current_app_role() NOT IN ('admin', 'manager', 'cashier') THEN
        RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_sale FROM public.sales
    WHERE upper(invoice_number) = upper(trim(p_invoice)) AND public.is_branch_member(branch_id);
    IF v_sale.id IS NULL THEN
        RAISE EXCEPTION 'No sale with invoice number %', trim(p_invoice);
    END IF;
    IF v_sale.status = 'draft' THEN
        RAISE EXCEPTION '% is a draft, not a completed sale', v_sale.invoice_number;
    END IF;

    SELECT COALESCE(return_window_days, 7) INTO v_days FROM public.app_settings ORDER BY created_at LIMIT 1;

    RETURN jsonb_build_object(
        'sale', jsonb_build_object(
            'id', v_sale.id, 'invoice_number', v_sale.invoice_number, 'created_at', v_sale.created_at,
            'customer_id', v_sale.customer_id, 'customer_name', v_sale.customer_name, 'cashier', v_sale.cashier,
            'total', v_sale.total, 'status', v_sale.status),
        'return_window_days', v_days,
        'within_window', v_sale.created_at >= now() - make_interval(days => v_days),
        'lines', (
            SELECT COALESCE(jsonb_agg(jsonb_build_object(
                'sale_line_id', sl.id, 'variant_id', sl.variant_id, 'description', sl.description, 'sku', sl.sku,
                'unit', sl.unit, 'quantity', sl.quantity, 'total', sl.total, 'is_gift', sl.is_gift,
                'returned', COALESCE((SELECT sum(rl.quantity) FROM public.return_lines rl WHERE rl.sale_line_id = sl.id), 0)
            ) ORDER BY sl.line_no), '[]'::jsonb)
            FROM public.sale_lines sl WHERE sl.sale_id = v_sale.id),
        'returns', (
            SELECT COALESCE(jsonb_agg(jsonb_build_object('return_no', r.return_no, 'refund_total', r.refund_total,
                                                         'created_at', r.created_at) ORDER BY r.created_at), '[]'::jsonb)
            FROM public.returns r WHERE r.sale_id = v_sale.id)
    );
END;
$$;

REVOKE ALL ON FUNCTION public.find_sale_for_return(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.find_sale_for_return(TEXT) TO authenticated;
