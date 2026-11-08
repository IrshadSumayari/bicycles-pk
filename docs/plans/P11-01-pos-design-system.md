# P11-01 POS design system (MatDash tokens, font, UI components)

**Branch:** `feat/ui-theme`
**Needs:** P11-00 read first. P19 and P20 merged.
**Files:** `src/index.css` (split into `src/css/`), new `src/css/**`, new `src/components/ui/*`,
new `src/components/shared/CardBox.tsx` (+ `TitleIconCard.tsx`), new `src/lib/utils.ts` (`cn`),
`src/lib/sweetAlert.ts` (theme only), `vite.config.ts`, `tsconfig*.json`, `vitest` config,
`package.json`, `package-lock.json`, `index.html` (title/theme colour only).
**No migration.**

Goal: after this plan **every existing screen already looks like MatDash** (font, colours, cards,
buttons, inputs, tables, badges, modals) without touching the screen components, because the app's
own utility classes (`card`, `btn`, `btn-primary`, `input`, `select`, …) are re-pointed at the
MatDash tokens.

## Steps

1. **Alias** `@/` → `src/` (Vite, TypeScript, Vitest). Add `src/lib/utils.ts` with the shadcn `cn()`
   (`clsx` + `tailwind-merge`).
2. **CSS structure** (copy from the template's `starterkit/src/css/`, trimmed as in P11-00):
   ```
   src/css/globals.css          ← entry; imported by main.tsx instead of index.css
   src/css/theme/tokens.css     ← :root tokens + @theme inline (from globals.css + default-colors.css :root)
   src/css/theme/dark.css       ← .dark tokens only (unused for now)
   src/css/layouts/{sidebar,header,container}.css
   src/css/override/reboot.css
   src/css/pages/{dashboards,auth}.css
   src/css/app-utilities.css    ← our @utility classes, rewritten (step 3)
   src/css/print.css            ← everything print-related from the old index.css, unchanged
   ```
   Import `@fontsource-variable/manrope` in `main.tsx`; set `font-family: 'Manrope Variable',
   sans-serif` on `body`; body text colour `var(--color-link)`, page background `var(--color-lightgray)`.
   Delete `src/index.css` only when every rule in it has a new home (list moved rules in the report).
   Keep the Tailwind v3 border-colour compatibility block, but point it at `var(--color-border)`.
3. **Re-point the existing utilities** (same class names, new look):
   - `card` → white, `rounded-[var(--radius-tw)]` (12px), `shadow-md`, no border.
   - `btn` → `rounded-md` (9px), `font-semibold`, `h-10`; `btn-primary` → `bg-primary
     hover:bg-primaryemphasis text-white`; `btn-secondary` → `bg-lightprimary text-primary
     hover:bg-primary hover:text-white`; `btn-success` / `btn-danger` → success / error with their
     emphasis hover; sizes keep their meaning.
   - `input`, `select`, `textarea` → `border-border rounded-md h-10 px-3 focus:ring-2
     focus:ring-lightprimary focus:border-primary`, placeholder `text-bodytext`.
   - Any other `@utility` in the old file (badges, tables, modal, status chips …): map greens →
     `success`/`lightsuccess`, reds → `error`/`lighterror`, ambers → `warning`/`lightwarning`,
     blues → `primary`/`lightprimary`, greys → `bodytext`/`border`/`lightgray`.
   - Add MatDash helpers used by copied markup: `border-ld`, `bg-hover`, `text-ld` (from the
     template CSS).
4. **UI components**: copy from `starterkit/src/components/ui/` into `src/components/ui/`:
   `button`, `card`, `badge`, `input`, `label`, `textarea`, `select`, `checkbox`, `switch`,
   `radio-group`, `tabs`, `table`, `dialog`, `sheet`, `dropdown-menu`, `popover`, `tooltip`,
   `separator`, `scroll-area`, `skeleton`, `avatar`, `progress`, `breadcrumb`, `sidebar` (P11-02
   needs it), `toast` + `toaster` + `hooks/use-toast.ts` and `hooks/use-mobile.ts`. Fix imports
   to `@/`. Remove anything that imports the Customizer or i18n.
   Copy `components/shared/CardBox.tsx` and `TitleIconCard.tsx` without the Customizer context.
   These components are **available**, not yet used by screens (P11-02/03 use them).
5. **SweetAlert2 theme** in `src/lib/sweetAlert.ts`: `customClass` / `buttonsStyling: false`
   so confirm uses `btn btn-primary btn-md`, cancel `btn btn-secondary btn-md`, popup `rounded-xl`
   with Manrope; icon colours from the tokens. Same function signatures.
6. **Generic hard-coded colours**: run `rg -n "(bg|text|border|ring|from|to)-(blue|indigo|gray|slate)-[0-9]+" src/components src/App.tsx`
   and replace **only** the colour part with the token equivalent (`blue-600`→`primary`,
   `blue-50/100`→`lightprimary`, `gray-50`→`lightgray`, `gray-500/600`→`bodytext`,
   `gray-900/800/700`→`link` or `dark`, `gray-100/200`→`border`). Do not change layout classes,
   texts or structure. Status colours (green/red/amber) → success/error/warning tokens.
   This is a mechanical change; keep each file's diff to colour classes only.
7. **Light and dark mode** (P11-00 decision 1):
   - `src/css/theme/dark.css` gets MatDash's full `.dark` token set; `default-colors.css` keeps all
     six `[data-color-theme=…]` presets.
   - New `src/context/ThemeContext.tsx` (from the template's `theme-context.tsx` +
     `CustomizerContext.tsx`, reduced): `mode: 'light' | 'dark' | 'system'`, `preset: 'BLUE_THEME' |
     'AQUA_THEME' | 'PURPLE_THEME' | 'GREEN_THEME' | 'CYAN_THEME' | 'ORANGE_THEME'`, `setMode`,
     `setPreset`, resolved mode; sets `class="dark"` and `data-color-theme` on `<html>`; listens to
     `prefers-color-scheme` while on System; stores both in `localStorage` key `pos-theme-v1`
     (try/catch). Wrap the app in it in `main.tsx`.
   - Inline script in `index.html` that applies the stored mode and preset before React loads.
   - Every `@utility` from step 3 gets its dark version (`card` → `dark:bg-darkgray
     dark:shadow-dark-md`, inputs → `dark:bg-dark dark:border-darkborder`, `btn-secondary` → dark
     lightprimary, text → `dark:text-white` / `dark:text-darklink`). Step 6's colour replacement adds
     the dark variant at the same time.
   - SweetAlert2 popups follow the mode.
   - `@media print` forces the light tokens so receipts, labels and slips always print black on white.
   No switch in the UI yet (P11-02 adds it); test by setting `localStorage` in the screenshots script.
8. **Unit tests**: `src/lib/utils.test.ts` for `cn()` merging; `ThemeContext.test.tsx` for stored
   value parsing (bad JSON, unknown preset → defaults) and System following the media query.

## Done when

- Every screen (till, tailoring, online orders, inventory, customers, reports, transactions,
  discounts, users, settings, login, receipt print, packing slip, order slip, labels) renders with
  Manrope and MatDash colours; screenshots of each in the report.
- The same screenshots in dark mode, with nothing unreadable (no dark text on dark background).
- Printing still looks the same as before, also when the screen is in dark mode (receipt, labels, slips); print preview screenshots.
- All checks pass; e2e smoke unchanged.
