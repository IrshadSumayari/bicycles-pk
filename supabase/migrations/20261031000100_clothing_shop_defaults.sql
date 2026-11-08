-- The initial schema seeded generic-store templates: categories such as
-- Electronics and Automotive, and three discounts priced in dollars. This is
-- a clothing shop that works in PKR, so remove the templates nobody uses.
-- Categories still linked to a product style are kept.

DELETE FROM public.categories c
WHERE c.name IN (
    'Electronics', 'Food & Beverage', 'Home & Garden', 'Books & Media',
    'Health & Beauty', 'Sports & Outdoors', 'Automotive'
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.product_styles s WHERE s.category_id = c.id
  );

DELETE FROM public.discounts
WHERE (name, description) IN (
  ('Senior Citizen Discount', '10% discount for senior citizens'),
  ('Student Discount', '5% discount for students'),
  ('Bulk Purchase Discount', '$10 off on purchases over $100')
);
