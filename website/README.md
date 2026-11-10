# Bicycles.pk storefront

The Next.js storefront shares the POS catalog and order APIs. It supports collections, products, bag, customer sign-in, checkout and order tracking. MatDash controls and light/dark/System appearance remain in place.

## Configuration

Public connection settings are documented in `.env.example`. `NEXT_PUBLIC_SITE_URL` is the deployed website origin used for canonical URLs, sitemap and robots. Put provider secrets only in Supabase function secrets, never here.

`content/brand.json` is the source for brand name, address and optional contacts. Phone, email, WhatsApp and social links stay hidden when unconfigured. Product photos come from Supabase Storage. Existing local campaign photographs and stored product photos are temporarily retained at the owner's request; automatic source-photo importing has been removed. Replace these with approved owner photos before a fully original-image launch.

New original pages and policies live in `content/pages/index.json`. Returns insert the live `catalog_policy` window. The owner's policy and launch checks are in `docs/operations/LAUNCH.md`, not public pages.

Montserrat headings (OFL, exact package version) and local Poppins body fonts are self-hosted; no Google Fonts requests. Logo assets are generated with the isolated dev-only Sharp tool in `scripts/brand/`. See that directory's README for regeneration.

Run from the repository root: `npm run web:lint`, `npm run web:test`, `npm run web:build`. For dependency changes use npm 10.9.9 from website, then `npx -y npm@10.9.9 ci --dry-run`.
