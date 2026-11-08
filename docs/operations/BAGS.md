# Bags & handbags

The **Bags** section in POS (admins and managers, beside Inventory and Jewellery) opens on **All bags**, which lists stock in every bag category. Choose Bags (general), Tote Bags, Shoulder Bags, Crossbody Bags, Top Handle Bags, Clutches, Mini Bags, Backpacks or Wallets & Purses to see one shape. The ordinary Inventory view still includes everything.

## Adding a bag

1. In Bags, choose a shape, then **Add style**. The category is filled in for new items.
2. Use **Ready-made item**. Enter the real material (for example Faux leather, Canvas, Suede).
3. Use the **Bag options** shortcuts: sizes (Mini, Small, Medium, Large, Extra large, One size) and colours. Use *Styles* for a design difference sold as its own item, for example Chain strap or Quilted. Use One size when the design comes in only one size.
4. Add variant rows. Each size/colour/style has its own SKU, barcode, price, cost and stock. A detachable strap or pouch sold with the bag is part of the same item.
5. Save, reopen the style and fill the **Website** tab:
   - **Bag details**: width, height and depth (outside edges, cm), strap drop (top of strap to top of bag), closure, compartments and what fits. Leave unknown details blank.
   - What's included (dust bag, detachable strap) and care instructions.
   - Real product photos, then publish.

The **Import** tab downloads tote, crossbody and wallet example rows in the usual CSV format. For bags, `color` is the colour and `fit` is the style. The examples are not real stock.

## Storefront

- `/bags` page: shop-by-shape strip and grid (the newest photographed product in each shape, otherwise an original line illustration), a "New in bags" row when bags are published, a size guide with what fits, and measuring/care guidance.
- Linked from the header menu, mobile category strip, footer, homepage and collections page. Shape links use exact category filters such as `/search?category=Tote%20Bags`, so products must be saved under those category names.
- Product pages for bags show Size / Colour / Style options, a details list (dimensions, strap drop, closure, compartments, what fits, material) and link to the bag size guide instead of the lingerie fit guide.

## How bag details are stored

No database change was needed. Bag details are saved as labelled lines (`Width: 30 cm`) in the existing product guide fit text, which the database already validates (2,000 characters). Lines that are not recognised stay as free notes. A dedicated column can replace this later if shoppers need to filter by size or material.
