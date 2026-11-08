# Brand assets

Install dev-only tools: `npm ci --prefix scripts/brand`.
Run `node scripts/brand/generate.mjs <path-to-owner-logo>` from the repository root. Without an argument it looks for `website/public/brand/ladyvogue-logo-source.png`. The original raster is not committed; the supplied local source is kept separately by the owner.

The pinned Apache-2.0 Sharp package samples the dominant foreground gold, removes the white background and isolated JPEG specks, trims the full lockup and creates the light/dark PNGs, M/thread mark, 32/180/512 favicons and 1200x630 sharing image. The mark crop (left 37% of the trimmed supplied lockup) stops before the separate lettering. If the owner supplies a different logo layout, review that crop before regenerating.

`palette.json` records the sampled gold, contrast calculations and crop bounds. The matching MatDash tokens are in website/styles/tokens.css. The generated OTP email reads website/content/brand.json; regenerate it when that configuration changes. No source campaign or product photos are processed by this script.

Montserrat is pinned in website/package.json and self-hosted through next/font/local. Its package includes the OFL-1.1 license; Poppins remains the existing local body font.

Header/footer use `ladyvogue-logo.png` and `ladyvogue-logo-dark.png` to avoid reusing an earlier brand�s image-cache keys. Generic filenames remain compatibility copies.
