-- Local development sample catalogue (applied by `supabase db reset`, never deployed).
-- Ten real bike models plus two accessories. Prices and stock are sample values for testing.
-- Photos: run `npm run seed:photos` after a reset to upload the free Unsplash photos listed in
-- scripts/seed-local/photos.json to local storage at the storage_path used below.

CREATE FUNCTION pg_temp.add_style(
 p_code TEXT, p_name TEXT, p_category TEXT, p_brand TEXT, p_material TEXT, p_year TEXT,
 p_description TEXT, p_specs JSONB, p_bulky BOOLEAN, p_variants JSONB, p_photos JSONB
) RETURNS UUID LANGUAGE plpgsql AS $$
DECLARE s UUID; v JSONB; vid UUID; cat UUID; floor UUID; i INT := 0; ph JSONB;
BEGIN
 INSERT INTO public.categories(name) VALUES (p_category) ON CONFLICT (name) DO NOTHING;
 SELECT id INTO cat FROM public.categories WHERE name = p_category;
 SELECT id INTO floor FROM public.locations WHERE code = 'FLOOR';
 INSERT INTO public.product_styles(code, name, kind, unit, category_id, brand, material, season,
  description, web_description, specs, bulky, published, slug)
 VALUES (p_code, p_name, 'item', 'piece', cat, p_brand, p_material, p_year, p_description, p_description,
  p_specs, p_bulky, true, lower(regexp_replace(p_name, '[^A-Za-z0-9]+', '-', 'g')))
 RETURNING id INTO s;
 FOR v IN SELECT * FROM jsonb_array_elements(p_variants) LOOP
  INSERT INTO public.product_variants(style_id, sku, size, color, fit, price, compare_at_price, published)
  VALUES (s, v->>'sku', v->>'size', v->>'color', v->>'fit', (v->>'price')::numeric,
   (v->>'compare_at')::numeric, true)
  RETURNING id INTO vid;
  INSERT INTO public.variant_costs(variant_id, unit_cost) VALUES (vid, round((v->>'price')::numeric * 0.72, 0));
  IF coalesce((v->>'stock')::numeric, 0) > 0 THEN
   PERFORM public.post_stock_movement(floor, vid, (v->>'stock')::numeric, 'opening');
  END IF;
 END LOOP;
 FOR ph IN SELECT * FROM jsonb_array_elements(p_photos) LOOP
  INSERT INTO public.product_images(style_id, variant_color, storage_path, alt, sort_order)
  VALUES (s, ph->>'color', 'styles/' || s || '/' || (ph->>'file'), ph->>'alt', i);
  i := i + 1;
 END LOOP;
 RETURN s;
END $$;

CREATE TEMP TABLE seed_styles(section TEXT, id UUID);

-- Bicycles
INSERT INTO seed_styles SELECT 'bicycles', pg_temp.add_style('TRK-FX2', 'Trek FX 2 Disc', 'Hybrid Bikes', 'Trek', 'Alpha Gold Aluminium', '2026',
 'A fast, light hybrid for commuting, fitness rides and weekend paths. Flat bars, a wide gear range and hydraulic disc brakes that stop confidently in any weather.',
 '{"frame":"Alpha Gold Aluminium","fork":"Alloy, rigid","wheel_size":"700c","tyres":"700 x 40c","gears":"18-speed","drivetrain":"Shimano Altus 2x9","brakes":"Hydraulic disc","suspension":"None","weight":"11.9 kg","max_load":"136 kg","rider_height":"155–195 cm","warranty":"Lifetime frame, 2 years parts"}',
 true,
 '[{"sku":"TRK-FX2-BLK-S","size":"S","color":"Black","price":285000,"stock":2},{"sku":"TRK-FX2-BLK-M","size":"M","color":"Black","price":285000,"stock":3},{"sku":"TRK-FX2-BLK-L","size":"L","color":"Black","price":285000,"stock":1},{"sku":"TRK-FX2-BLU-M","size":"M","color":"Blue","price":285000,"stock":2},{"sku":"TRK-FX2-BLU-L","size":"L","color":"Blue","price":285000,"stock":0}]',
 '[{"file":"trek-fx2-blue.jpg","color":"Blue","alt":"Blue hybrid bike on a white floor"},{"file":"trek-fx2-black.jpg","color":"Black","alt":"Black hybrid bike leaning on a handrail"}]');

INSERT INTO seed_styles SELECT 'bicycles', pg_temp.add_style('GNT-ESC3', 'Giant Escape 3', 'City & Commuter', 'Giant', 'ALUXX Aluminium', '2026',
 'An easy-riding city bike with an upright position, 21 gears and puncture-resistant tyres. Mounts for a rack and mudguards make it a dependable daily commuter.',
 '{"frame":"ALUXX Aluminium","fork":"Steel, rigid","wheel_size":"700c","tyres":"700 x 38c","gears":"21-speed","drivetrain":"Shimano Tourney 3x7","brakes":"V-brake (rim)","suspension":"None","weight":"12.6 kg","max_load":"136 kg","rider_height":"150–190 cm","warranty":"Lifetime frame, 1 year parts"}',
 true,
 '[{"sku":"GNT-ESC3-GRY-S","size":"S","color":"Grey","price":165000,"stock":2},{"sku":"GNT-ESC3-GRY-M","size":"M","color":"Grey","price":165000,"compare_at":185000,"stock":4},{"sku":"GNT-ESC3-GRY-L","size":"L","color":"Grey","price":165000,"stock":2}]',
 '[{"file":"giant-escape3-grey.jpg","color":"Grey","alt":"Grey city bike side view"}]');

INSERT INTO seed_styles SELECT 'bicycles', pg_temp.add_style('BRM-CEXP', 'Brompton C Line Explore', 'Folding Bikes', 'Brompton', 'Steel', '2026',
 'The classic folding bike: folds in seconds to fit under a desk, in a car boot or on a train. Six gears cover city hills, and the steel frame rides smoothly.',
 '{"frame":"Steel","wheel_size":"16\"","tyres":"16 x 1.35\"","gears":"6-speed","drivetrain":"2-speed derailleur with 3-speed hub","brakes":"Dual-pivot rim","suspension":"Rear elastomer","weight":"11.8 kg","max_load":"110 kg","rider_height":"150–195 cm","folded_size":"58.5 x 56.5 x 27 cm","warranty":"7 years frame, 2 years parts"}',
 true,
 '[{"sku":"BRM-CEXP-BLU","size":"One size","color":"Blue","price":650000,"stock":1}]',
 '[{"file":"brompton-blue.jpg","color":"Blue","alt":"Blue and white folding bike parked outdoors"},{"file":"brompton-street.jpg","color":null,"alt":"Folding bike parked by a vending machine"}]');

INSERT INTO seed_styles SELECT 'bicycles', pg_temp.add_style('ELC-TWN7', 'Electra Townie Original 7D', 'Cruisers', 'Electra', 'Aluminium', '2026',
 'A relaxed cruiser with Flat Foot Technology: you sit comfortably but can put both feet flat on the ground at a stop. Seven gears and a cushioned saddle.',
 '{"frame":"Aluminium, step-through","fork":"Steel","wheel_size":"26\"","tyres":"26 x 2.35\"","gears":"7-speed","drivetrain":"Shimano Tourney","brakes":"Linear-pull (rim)","suspension":"None","weight":"15.4 kg","max_load":"136 kg","rider_height":"152–193 cm","warranty":"Lifetime frame, 2 years parts"}',
 true,
 '[{"sku":"ELC-TWN7-YEL","size":"One size","color":"Cream","price":145000,"stock":3},{"sku":"ELC-TWN7-MNT","size":"One size","color":"Mint","price":145000,"stock":2}]',
 '[{"file":"townie-cream.jpg","color":"Cream","alt":"Cruiser bike leaning on a yellow wall"},{"file":"townie-mint.jpg","color":"Mint","alt":"Cruiser bike against a wall"}]');

-- Sports
INSERT INTO seed_styles SELECT 'sports', pg_temp.add_style('SPZ-RCK29', 'Specialized Rockhopper Sport 29', 'Mountain Bikes', 'Specialized', 'Premium A1 Aluminium', '2026',
 'A capable hardtail for first trail rides and rough roads. Big 29-inch wheels roll over rocks, the 80 mm fork smooths bumps and hydraulic discs keep control.',
 '{"frame":"Premium A1 Aluminium","fork":"SR Suntour XCM, 80 mm travel","wheel_size":"29\"","tyres":"29 x 2.35\"","gears":"18-speed","drivetrain":"microSHIFT Advent 2x9","brakes":"Hydraulic disc","suspension":"Front","weight":"14.0 kg","max_load":"125 kg","rider_height":"160–198 cm","warranty":"Lifetime frame, 1 year parts"}',
 true,
 '[{"sku":"SPZ-RCK29-ORG-M","size":"M","color":"Orange","price":260000,"stock":2},{"sku":"SPZ-RCK29-ORG-L","size":"L","color":"Orange","price":260000,"stock":2},{"sku":"SPZ-RCK29-ORG-XL","size":"XL","color":"Orange","price":260000,"stock":1}]',
 '[{"file":"rockhopper-orange.jpg","color":"Orange","alt":"Orange and black mountain bike on a hill"},{"file":"rockhopper-trail.jpg","color":null,"alt":"Mountain bike on a trail at sunset"}]');

INSERT INTO seed_styles SELECT 'sports', pg_temp.add_style('CND-CAAD3', 'Cannondale CAAD Optimo 3', 'Road Bikes', 'Cannondale', 'SmartForm C2 Aluminium', '2026',
 'A light, responsive aluminium road bike with race-inspired geometry and Shimano Sora shifting. Fast on group rides, comfortable enough for long Sunday miles.',
 '{"frame":"SmartForm C2 Aluminium","fork":"Carbon blades","wheel_size":"700c","tyres":"700 x 28c","gears":"18-speed","drivetrain":"Shimano Sora 2x9","brakes":"Dual-pivot rim","suspension":"None","weight":"9.4 kg","max_load":"125 kg","rider_height":"160–195 cm","warranty":"Lifetime frame, 2 years parts"}',
 true,
 '[{"sku":"CND-CAAD3-BLK-52","size":"52","color":"Black","price":420000,"stock":1},{"sku":"CND-CAAD3-BLK-54","size":"54","color":"Black","price":420000,"stock":2},{"sku":"CND-CAAD3-BLK-56","size":"56","color":"Black","price":420000,"stock":1},{"sku":"CND-CAAD3-WHT-54","size":"54","color":"White","price":420000,"stock":1}]',
 '[{"file":"caad-black.jpg","color":"Black","alt":"Black road bike side view"},{"file":"caad-black-wall.jpg","color":"Black","alt":"Black road bike against a wooden wall"},{"file":"caad-white.jpg","color":"White","alt":"White road bike in a studio"}]');

INSERT INTO seed_styles SELECT 'sports', pg_temp.add_style('MGS-LEG20', 'Mongoose Legion L20', 'BMX', 'Mongoose', 'Hi-ten Steel', '2026',
 'A tough freestyle BMX for skateparks and street. Strong steel frame, 3-piece cranks and a U-brake, ready for pegs and first tricks.',
 '{"frame":"Hi-ten Steel","fork":"Hi-ten Steel","wheel_size":"20\"","tyres":"20 x 2.4\"","gears":"Single speed","brakes":"U-brake (rear)","suspension":"None","weight":"12.2 kg","max_load":"100 kg","rider_height":"140–175 cm","warranty":"1 year frame"}',
 true,
 '[{"sku":"MGS-LEG20-BLK","size":"20\"","color":"Black","price":95000,"stock":3}]',
 '[{"file":"legion-black.jpg","color":"Black","alt":"BMX bike parked beside a fence"}]');

-- Kids
INSERT INTO seed_styles SELECT 'kids', pg_temp.add_style('STR-12SP', 'Strider 12 Sport', 'Balance Bikes', 'Strider', 'Steel', '2026',
 'The balance bike that teaches children to ride without training wheels. Light, adjustable from 18 months, with a padded saddle and tool-free height changes.',
 '{"frame":"Steel","wheel_size":"12\"","tyres":"Puncture-proof EVA foam","gears":"None (no pedals)","brakes":"None","weight":"3.0 kg","max_load":"27 kg","age_range":"18 months – 5 years","rider_height":"76–110 cm","warranty":"1 year"}',
 false,
 '[{"sku":"STR-12SP-RED","size":"12\"","color":"Red","price":32000,"stock":5},{"sku":"STR-12SP-BLU","size":"12\"","color":"Blue","price":32000,"stock":4}]',
 '[{"file":"strider-red.jpg","color":null,"alt":"Child riding a small bike outdoors"}]');

INSERT INTO seed_styles SELECT 'kids', pg_temp.add_style('TRK-PRE16', 'Trek Precaliber 16', 'Training Wheel Bikes', 'Trek', 'Steel', '2026',
 'A first pedal bike with removable training wheels, a coaster brake and hand brake, and a chain guard to keep little legs clean.',
 '{"frame":"Steel","wheel_size":"16\"","tyres":"16 x 2.125\"","gears":"Single speed","brakes":"Coaster and hand brake","weight":"8.7 kg","max_load":"36 kg","age_range":"4–6 years","rider_height":"99–117 cm","warranty":"Lifetime frame"}',
 false,
 '[{"sku":"TRK-PRE16-BLU","size":"16\"","color":"Blue","price":55000,"stock":4}]',
 '[{"file":"precaliber-blue.jpg","color":null,"alt":"Boy riding a bicycle on a sunny day"}]');

-- E-bikes
INSERT INTO seed_styles SELECT 'ebikes', pg_temp.add_style('AVT-PC500', 'Aventon Pace 500.3', 'City E-bikes', 'Aventon', 'Aluminium', '2026',
 'A powerful city e-bike with a torque sensor that feels natural, five levels of assist, integrated lights and a colour display. Arrive fresh, even in the heat.',
 '{"frame":"Aluminium","fork":"Alloy, rigid","wheel_size":"27.5\"","tyres":"27.5 x 2.2\"","gears":"8-speed","drivetrain":"Shimano Altus","brakes":"Hydraulic disc","suspension":"None","weight":"24.5 kg","max_load":"136 kg","rider_height":"160–193 cm","motor":"500 W rear hub","battery":"48 V 14 Ah (672 Wh)","range":"Up to 96 km","warranty":"2 years"}',
 true,
 '[{"sku":"AVT-PC500-YEL-M","size":"M","color":"Yellow","price":520000,"stock":1},{"sku":"AVT-PC500-YEL-L","size":"L","color":"Yellow","price":520000,"stock":1}]',
 '[{"file":"pace-yellow.jpg","color":"Yellow","alt":"Pale yellow electric bike on a street"},{"file":"pace-riding.jpg","color":null,"alt":"Two people riding electric bikes"}]');

-- Accessories (not bulky)
INSERT INTO seed_styles SELECT 'accessories', pg_temp.add_style('GIR-REG', 'Giro Register MIPS Helmet', 'Helmets', 'Giro', 'EPS foam, polycarbonate shell', '2026',
 'A comfortable everyday helmet with MIPS rotational protection, 22 vents and a one-hand fit dial.',
 '{"weight":"310 g","warranty":"1 year"}',
 false,
 '[{"sku":"GIR-REG-BLK","size":"One size","color":"Black","price":14500,"stock":8}]',
 '[{"file":"helmet-black.jpg","color":null,"alt":"Black vented bike helmet"}]');

INSERT INTO seed_styles SELECT 'accessories', pg_temp.add_style('LZN-LITE', 'Lezyne Lite Drive 1000+ Front Light', 'Lights', 'Lezyne', 'Aluminium', '2026',
 'A 1000-lumen USB-C rechargeable front light with daytime flash mode, for dark roads and dawn rides.',
 '{"weight":"143 g","warranty":"2 years"}',
 false,
 '[{"sku":"LZN-LITE-BLK","size":"One size","color":"Black","price":12500,"stock":6}]',
 '[{"file":"light-black.jpg","color":null,"alt":"Black bike front light"}]');

-- One published collection per section, so product pages can show sibling models.
INSERT INTO public.collections(slug, name, published, sort_order) VALUES
 ('sample-bicycles', 'Bicycles', true, 1), ('sample-sports', 'Sports', true, 2), ('sample-kids', 'Kids', true, 3),
 ('sample-ebikes', 'E-bikes', true, 4), ('sample-accessories', 'Accessories', true, 5);
INSERT INTO public.collection_styles(collection_id, style_id)
SELECT c.id, s.id FROM seed_styles s JOIN public.collections c ON c.slug = 'sample-' || s.section;

-- Bulky delivery and assembly so checkout shows both.
UPDATE public.app_settings SET bulky_delivery_fee = 1500, assembly_fee = 2000;
