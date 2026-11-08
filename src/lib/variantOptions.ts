import { buildSku } from "./sku";

export function uniqueOptions(values: string[]): string[] {
  const seen = new Set<string>();
  return values
    .map((v) => v.trim())
    .filter((v) => {
      const key = v.toLowerCase();
      if (!v || seen.has(key)) return false;
      seen.add(key);
      return true;
    });
}

type Option = { size?: string; color?: string; fit?: string };
const identity = (v: Option) =>
  JSON.stringify(
    [v.size, v.color, v.fit].map((x) => (x || "").trim().toLowerCase()),
  );

// One row per size x colour x fit; supplier labels are kept as entered.
export function missingVariants(
  code: string,
  sizes: string[],
  colors: string[],
  fits: string[],
  existing: (Option & { sku: string })[],
) {
  const options = (values: string[]): (string | undefined)[] => {
    const clean = uniqueOptions(values);
    return clean.length ? clean : [undefined];
  };
  const seen = new Set(existing.map(identity));
  const skus = new Set(existing.map((v) => v.sku.trim().toUpperCase()));
  const result: (Option & { sku: string })[] = [];
  for (const color of options(colors))
    for (const size of options(sizes))
      for (const fit of options(fits)) {
        const variant = { size, color, fit };
        const key = identity(variant);
        if (seen.has(key)) continue;
        seen.add(key);
        const base = buildSku(code, size, color, fit);
        let sku = base;
        let suffix = 2;
        while (skus.has(sku)) sku = `${base}-${suffix++}`;
        skus.add(sku);
        result.push({ ...variant, sku });
      }
  return result;
}

export function duplicateVariantError(
  rows: (Option & { sku: string; barcode?: string })[],
): string | undefined {
  const skus = new Set<string>(),
    barcodes = new Set<string>(),
    combinations = new Set<string>();
  for (const row of rows) {
    const sku = row.sku.trim().toUpperCase();
    const barcode = row.barcode?.trim().toUpperCase();
    if (skus.has(sku)) return `SKU ${sku} is used more than once.`;
    if (barcode && barcodes.has(barcode))
      return `Barcode ${barcode} is used more than once.`;
    if (combinations.has(identity(row)))
      return "Each size, color and fit combination must appear only once.";
    skus.add(sku);
    if (barcode) barcodes.add(barcode);
    combinations.add(identity(row));
  }
}
