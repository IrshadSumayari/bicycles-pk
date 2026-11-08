import { buildSku } from "./sku";

export const LADYVOGUE_CATEGORIES = [
  "Bras",
  "Panties",
  "Lingerie Sets",
  "Nightwear",
  "Shapewear",
  "Camisoles",
  "Robes",
];
// Shown under a category in pickers. "Lingerie Sets" is the bra + panty pair
// category (bra sizes apply; the shop lists it as "Matching sets").
export const CATEGORY_HINTS: Record<string, string> = {
  "lingerie sets": "Bra & panty sets, sold as one item",
};
export const LETTER_SIZES = ["XS", "S", "M", "L", "XL", "XXL", "3XL"];
export const BRA_BANDS = [
  "28",
  "30",
  "32",
  "34",
  "36",
  "38",
  "40",
  "42",
  "44",
  "46",
];
export const BRA_CUPS = ["AA", "A", "B", "C", "D", "DD", "E", "F", "FF", "G"];

// What kind of lingerie a style is, so the form shows only the fields and
// size shortcuts that apply. null = not lingerie (or not yet known).
export type LingerieKind = "bra" | "set" | "bottom" | "apparel";

const SET_WORDS = /\b(sets?|pairs?|pant(y|ies)|pent(y|ies)|briefs?|knickers?)\b/;
function kindFromText(text: string): LingerieKind | null {
  const t = text.toLowerCase();
  const bra = /\b(bras?|bralettes?)\b/.test(t);
  if ((bra && SET_WORDS.test(t)) || /\blingerie sets?\b|\bmatching sets?\b/.test(t)) return "set";
  if (bra) return "bra";
  if (/\b(pant(y|ies)|pent(y|ies)|briefs?|thongs?|knickers?|boyshorts?|bottoms?|underwear)\b/.test(t)) return "bottom";
  if (/\b(nightwear|nightdress(es)?|nighties?|pyjamas?|pajamas?|sleepwear|robes?|camisoles?|camis?|shapewear|slips?|loungewear)\b/.test(t)) return "apparel";
  return null;
}

// The category decides; the name is used while no category is chosen, and
// to spot a bra + panty pair filed under a bra category.
export function lingerieKind(category?: string, name?: string): LingerieKind | null {
  const fromCategory = kindFromText(category ?? "");
  const fromName = kindFromText(name ?? "");
  if (fromCategory === "bra" && fromName === "set") return "set";
  if (fromCategory || (category ?? "").trim()) return fromCategory;
  return fromName;
}

// Lingerie detail fields that apply to each kind (all of them when unknown).
export const LINGERIE_FIELDS: Record<LingerieKind, readonly string[]> = {
  bra: ["product_type", "padding", "wire", "coverage", "sizing_system", "composition"],
  set: ["product_type", "padding", "wire", "coverage", "sizing_system", "composition"],
  bottom: ["product_type", "coverage", "composition"],
  apparel: ["product_type", "composition"],
};
// Product-type choices that fit each kind.
export const LINGERIE_TYPES: Record<LingerieKind, readonly string[]> = {
  bra: ["everyday", "t_shirt", "bralette", "sports", "nursing", "minimizer", "push_up", "strapless"],
  set: ["matching_set", "everyday", "t_shirt", "bralette", "push_up"],
  bottom: ["brief", "thong", "boyshort"],
  apparel: ["pyjama_set", "nightdress", "robe", "shapewear", "camisole"],
};

// Size labels for a bra + panty set sold as one item: "34B / M".
// Every bra size is paired with every bottom size; remove the ones you don't stock.
export function setSizes(bra: string[], bottom: string[]): string[] {
  const tops = uniqueOptions(bra), bottoms = uniqueOptions(bottom);
  if (!tops.length) return bottoms;
  if (!bottoms.length) return tops;
  return tops.flatMap((top) => bottoms.map((b) => `${top} / ${b}`));
}

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

export function braSizes(bands: string[], cups: string[]): string[] {
  return uniqueOptions(bands).flatMap((band) =>
    uniqueOptions(cups).map((cup) => band + cup.toUpperCase()),
  );
}

type Option = { size?: string; color?: string; fit?: string };
const identity = (v: Option) =>
  JSON.stringify(
    [v.size, v.color, v.fit].map((x) => (x || "").trim().toLowerCase()),
  );

// Keep supplier labels intact: DD and E are distinct, not converted between sizing systems.
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
