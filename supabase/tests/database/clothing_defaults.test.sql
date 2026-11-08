BEGIN;
SELECT plan(5);
SELECT is((SELECT count(*)::int FROM categories WHERE name IN ('Electronics','Food & Beverage','Home & Garden','Books & Media','Health & Beauty','Sports & Outdoors','Automotive')),0,'non-clothing template categories removed');
SELECT is((SELECT count(*)::int FROM categories WHERE name='Clothing'),1,'Clothing kept');
SELECT is((SELECT count(*)::int FROM categories WHERE name='General'),0,'unused General template removed');
SELECT is((SELECT count(*)::int FROM discounts WHERE name IN ('Senior Citizen Discount','Student Discount','Bulk Purchase Discount')),0,'template discounts removed');
SELECT is((SELECT count(*)::int FROM discounts WHERE description LIKE '%$%'),0,'no dollar amounts in discounts');
SELECT * FROM finish();
ROLLBACK;
