const skuPart = (value?: string, max = 4) =>
  (value || '').toUpperCase().replace(/[^A-Z0-9]+/g, '').slice(0, max);

// SKU for one variant of a style, e.g. SK-001 + L + Navy White -> SK-001-NAVY-L.
// A bra + panty set size such as "34DD / XL" keeps both parts (34DDXL).
export function buildSku(code: string, size?: string, color?: string, fit?: string): string {
  return [code.toUpperCase().trim(), skuPart(color), skuPart(size, size?.includes('/') ? 6 : 4), skuPart(fit)].filter(Boolean).join('-');
}
