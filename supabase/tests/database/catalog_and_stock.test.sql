-- Catalog, cost privacy, stock ledger, reservations, idempotency, public catalog.
BEGIN;
SELECT plan(30);

-- Staff fixtures: admin (bootstrapped), manager, cashier
INSERT INTO auth.users (id, email, raw_user_meta_data, raw_app_meta_data) VALUES
    ('00000000-0000-0000-0000-00000000aa01', 'admin@t.local',   '{"name":"Admin"}', '{}'),
    ('00000000-0000-0000-0000-00000000aa02', 'manager@t.local', '{"name":"Manager"}', '{"account_type":"staff"}'),
    ('00000000-0000-0000-0000-00000000aa03', 'cashier@t.local', '{"name":"Cashier"}', '{"account_type":"staff"}');
SELECT app_private.bootstrap_admin('admin@t.local'); -- first administrator (no longer the first sign-up)
UPDATE public.users SET role = 'manager', active = true WHERE id = '00000000-0000-0000-0000-00000000aa02';
UPDATE public.users SET active = true WHERE id = '00000000-0000-0000-0000-00000000aa03';

CREATE TEMP TABLE ids AS
SELECT
    (SELECT l.id FROM locations l JOIN branches b ON b.id = l.branch_id WHERE b.code = 'MAIN' AND l.code = 'FLOOR') AS floor,
    (SELECT id FROM size_schemes WHERE code = 'FRAME') AS frame;
GRANT SELECT ON ids TO authenticated;

-- ---------------------------------------------------------------------
-- Manager builds a style with two variants
-- ---------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000aa02","role":"authenticated","aal":"aal2"}';

SELECT lives_ok($$
    INSERT INTO product_styles (id, code, name, kind, unit, size_scheme_id, published, slug)
    VALUES ('00000000-0000-0000-0000-0000000005a1', 'SK-NAVY', 'Navy City Bike', 'item', 'piece',
            (SELECT frame FROM ids), true, 'navy-city-bike')
$$, 'manager can create a style');
SELECT lives_ok($$
    INSERT INTO product_variants (id, style_id, sku, size, color, price) VALUES
        ('00000000-0000-0000-0000-0000000005b1', '00000000-0000-0000-0000-0000000005a1', 'SK-NAVY-M', 'M', 'Navy', 4500),
        ('00000000-0000-0000-0000-0000000005b2', '00000000-0000-0000-0000-0000000005a1', 'SK-NAVY-L', 'L', 'Navy', 4500)
$$, 'manager can create variants');
SELECT lives_ok($$
    INSERT INTO variant_costs (variant_id, unit_cost) VALUES ('00000000-0000-0000-0000-0000000005b1', 2100)
$$, 'manager can record cost');
SELECT lives_ok($$
    INSERT INTO barcodes (code, variant_id) VALUES ('8961000000011', '00000000-0000-0000-0000-0000000005b1')
$$, 'manager can assign a barcode');
SELECT throws_ok($$
    INSERT INTO barcodes (code, variant_id) VALUES ('8961000000011', '00000000-0000-0000-0000-0000000005b2')
$$, '23505', NULL, 'a barcode belongs to one variant only');
SELECT throws_ok($$
    INSERT INTO product_variants (style_id, sku, size, color, price)
    VALUES ('00000000-0000-0000-0000-0000000005a1', 'SK-NAVY-M2', 'M', 'Navy', 4500)
$$, '23505', NULL, 'the same size and color cannot be added twice');
SELECT throws_ok($$
    INSERT INTO product_styles (code, name, kind, unit) VALUES ('BAD', 'Bad', 'pack', 'piece')
$$, '23514', NULL, 'a pack must be sold as a set');

-- Opening stock and adjustments
SELECT lives_ok($$
    SELECT adjust_stock('00000000-0000-0000-0000-0000000005b1', (SELECT floor FROM ids), 3, 'Opening count', 'opening',
                        '00000000-0000-0000-0000-00000000f001')
$$, 'manager can post opening stock');
SELECT lives_ok($$
    SELECT adjust_stock('00000000-0000-0000-0000-0000000005b1', (SELECT floor FROM ids), 3, 'Opening count', 'opening',
                        '00000000-0000-0000-0000-00000000f001')
$$, 'retrying the same request is accepted');
SELECT is((SELECT on_hand FROM stock_balances WHERE variant_id = '00000000-0000-0000-0000-0000000005b1'), 3.000000,
          'a retried request is applied only once');
SELECT is((SELECT count(*)::int FROM stock_movements WHERE variant_id = '00000000-0000-0000-0000-0000000005b1'), 1,
          'one movement for a retried request');
SELECT throws_ok($$
    SELECT adjust_stock('00000000-0000-0000-0000-0000000005b1', (SELECT floor FROM ids), 1.5, 'Half a tube')
$$, NULL, NULL, 'items only take whole quantities');
SELECT throws_ok($$
    SELECT adjust_stock('00000000-0000-0000-0000-0000000005b1', (SELECT floor FROM ids), -5, 'Too many')
$$, NULL, NULL, 'stock cannot go below zero');
SELECT throws_ok($$
    SELECT adjust_stock('00000000-0000-0000-0000-0000000005b1', (SELECT floor FROM ids), -1, '  ')
$$, NULL, NULL, 'adjustments need a reason');

-- Reservations
SELECT lives_ok($$
    SELECT reserve_stock('00000000-0000-0000-0000-0000000005b1', (SELECT floor FROM ids), 2, 'web', 'online_order', NULL,
                         now() - interval '1 minute')
$$, 'stock can be reserved');
SELECT is((SELECT available FROM variant_stock WHERE variant_id = '00000000-0000-0000-0000-0000000005b1'), 1.000000,
          'reservations reduce available stock');
SELECT throws_ok($$
    SELECT adjust_stock('00000000-0000-0000-0000-0000000005b1', (SELECT floor FROM ids), -2, 'Damaged')
$$, NULL, NULL, 'reserved stock cannot be adjusted away');
SELECT throws_ok($$
    SELECT reserve_stock('00000000-0000-0000-0000-0000000005b1', (SELECT floor FROM ids), 2, 'pos')
$$, NULL, NULL, 'cannot reserve more than available');

-- Cashier
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000aa03","role":"authenticated","aal":"aal2"}';
SELECT is((SELECT count(*)::int FROM product_variants), 2, 'cashier can read variants');
SELECT is((SELECT count(*)::int FROM variant_costs), 0, 'cashier cannot read cost prices');
SELECT is((SELECT count(*)::int FROM stock_movements), 0, 'cashier cannot read the movement history');
SELECT throws_ok($$
    SELECT adjust_stock('00000000-0000-0000-0000-0000000005b1', (SELECT floor FROM ids), 10, 'Free stock')
$$, '42501', NULL, 'cashier cannot adjust stock');
SELECT throws_ok($$
    INSERT INTO product_variants (style_id, sku, price) VALUES ('00000000-0000-0000-0000-0000000005a1', 'X', 1)
$$, '42501', NULL, 'cashier cannot create variants');

-- Ledger is append-only, even for admins
RESET ROLE;
SET LOCAL "request.jwt.claims" = '';
SELECT throws_ok($$ UPDATE stock_movements SET quantity = 100 $$, '42501', NULL, 'movements cannot be edited');
SELECT throws_ok($$ DELETE FROM stock_movements $$, '42501', NULL, 'movements cannot be deleted');

-- Expiry gives reserved stock back
SELECT is(public.expire_stock_reservations(), 1, 'expired reservation is released');
SELECT is((SELECT available FROM variant_stock WHERE variant_id = '00000000-0000-0000-0000-0000000005b1'), 3.000000,
          'available stock restored after expiry');

-- Website visitors
SET LOCAL ROLE anon;
SELECT is((SELECT count(*)::int FROM public_catalog), 2, 'published variants are visible to visitors');
SELECT is(
    (SELECT stock_level FROM public_catalog WHERE sku = 'SK-NAVY-L'), 'out_of_stock',
    'visitors see a stock level, not quantities'
);
SELECT throws_ok($$ SELECT count(*) FROM product_variants $$, '42501', NULL, 'visitors cannot read catalog tables directly');

SELECT * FROM finish();
ROLLBACK;
