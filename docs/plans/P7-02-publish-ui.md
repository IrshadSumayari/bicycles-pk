# P7-02 Publishing from the POS

**Branch:** `feat/web-publish-ui`
**Needs:** P7-01 merged.
**Files:** `src/components/inventory/StyleModal.tsx` (new "Website" tab or section), new
`src/components/inventory/WebsitePanel.tsx`, new `src/components/inventory/ImageManager.tsx`,
new `src/components/inventory/CollectionsManager.tsx`, `src/lib/services.ts` (`webCatalogService`),
new `src/lib/images.ts` (+ test), `src/lib/queryClient.ts`.
**No migration** (if you find a missing database piece, stop and report it instead of adding one).

## Why
Managers must publish products to the website from the same place they edit them, with images,
without a developer.

## Steps
1. **Image handling** `src/lib/images.ts`:
   - `resizeImage(file, maxSide = 1600, quality = 0.82): Promise<Blob>` using a canvas,
     output `image/webp` (fallback `image/jpeg` if the browser can't encode webp).
   - `slugify(text)` (lowercase, ASCII, hyphens, max 80 chars) — unit-test with Urdu/English mixes
     and punctuation (Urdu letters are dropped; if nothing is left, return '').
   - `publicImageUrl(path)` via `supabase.storage.from('product-images').getPublicUrl(path)` in the service.
   - Reject files > 10 MB before resizing and non-image types; show a clear message.
2. **Service** `webCatalogService`: `uploadImage(styleId, blob)` → path
   `styles/<styleId>/<uuid>.webp`, `saveImages(styleId, images)`, `publish(styleId, on, dryRun)`,
   `collections.list/save/setStyles`.
3. **Website section in the style editor** (only admin/manager):
   - Toggle **Published on website** — on change call `publish_style` with dry run first; if
     problems, show them as a checklist and keep it off.
   - Slug (auto from name, editable, validated), web title, web description (textarea with
     character count), per-variant "show online" checkboxes.
   - **Images**: drag-and-drop/upload multiple, thumbnails, reorder (up/down buttons is enough),
     alt text, optional color tag, delete (also delete the object from storage).
   - **Preview** card: how the product card will look on the site (title, price range, first image,
     stock band).
4. **Collections manager** (Inventory → "Collections" tab): list, create/edit (name, slug,
   description, hero image, dates, published), add/remove styles with a search picker, reorder.
5. Inventory list: a "Online" badge on published styles and a filter "Published / Not published".

## Tests
- Vitest for `slugify` and the file validation helper (pure parts of `images.ts`).
- Manual against local Supabase: upload 3 images, publish, open `catalog_product(slug)` in
  Supabase Studio as anon (or `curl` the REST rpc endpoint with the anon key) and see the paths.

## Done when
All guide checks pass; a manager can publish a style with images and see it in `catalog_list`.
