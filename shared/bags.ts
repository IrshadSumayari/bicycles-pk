// Bags, handbags, purses and wallets. Categories are stored by exact name,
// like jewellery, so POS sections and storefront links use the same filter.
export const bagCategories = [
  {
    name: "Bags",
    slug: "bags",
    description: "Every shape, for every plan.",
    sizes: ["Mini", "Small", "Medium", "Large", "One size"],
  },
  {
    name: "Tote Bags",
    slug: "tote-bags",
    description: "Room for the whole day, and then some.",
    sizes: ["Medium", "Large", "Extra large"],
  },
  {
    name: "Shoulder Bags",
    slug: "shoulder-bags",
    description: "Easy, polished and always within reach.",
    sizes: ["Small", "Medium", "Large"],
  },
  {
    name: "Crossbody Bags",
    slug: "crossbody-bags",
    description: "Hands free, out and about.",
    sizes: ["Mini", "Small", "Medium"],
  },
  {
    name: "Top Handle Bags",
    slug: "top-handle-bags",
    description: "Structured shapes for a put-together look.",
    sizes: ["Small", "Medium", "Large"],
  },
  {
    name: "Clutches",
    slug: "clutches",
    description: "For evenings, weddings and dinners out.",
    sizes: ["One size", "Small", "Medium"],
  },
  {
    name: "Mini Bags",
    slug: "mini-bags",
    description: "Just the essentials, beautifully.",
    sizes: ["Mini", "One size"],
  },
  {
    name: "Backpacks",
    slug: "backpacks",
    description: "Carry more, with a little style.",
    sizes: ["Small", "Medium", "Large"],
  },
  {
    name: "Wallets & Purses",
    slug: "wallets-purses",
    description: "Cards, cash and keys, kept together.",
    sizes: ["One size", "Small", "Long"],
  },
] as const;

export const bagColours = [
  "Black",
  "Brown",
  "Tan",
  "Beige",
  "Ivory",
  "Maroon",
  "Blush",
  "Olive",
];

// Typical outer dimensions and what usually fits. These are guidance for
// shoppers; each product lists its own measured dimensions.
export const bagSizeGuide = [
  {
    size: "Mini",
    dimensions: "under 18 cm wide",
    fits: "Phone, cards, lipstick and keys",
  },
  {
    size: "Small",
    dimensions: "18–25 cm wide",
    fits: "Phone, compact wallet, sunglasses",
  },
  {
    size: "Medium",
    dimensions: "25–32 cm wide",
    fits: "Phone, full wallet, small pouch, water bottle",
  },
  {
    size: "Large",
    dimensions: "32–40 cm wide",
    fits: "A4 folder, 13″ tablet, everyday essentials",
  },
  {
    size: "Extra large",
    dimensions: "over 40 cm wide",
    fits: "13–14″ laptop, change of clothes, travel items",
  },
] as const;

export function isBagCategory(category: string | null | undefined): boolean {
  const value = category?.trim().toLowerCase();
  return bagCategories.some((c) => c.name.toLowerCase() === value);
}
export function bagSizes(category: string): readonly string[] {
  return (
    bagCategories.find(
      (c) => c.name.toLowerCase() === category.trim().toLowerCase(),
    )?.sizes ?? []
  );
}
export function bagCategoryHref(category: string): string {
  return "/search?category=" + encodeURIComponent(category);
}

// Bag details are kept as labelled lines ("Width: 30 cm") in the product
// guide's existing fit text, so no database change is needed and the text
// still reads well anywhere it is shown as-is.
export const bagDetailFields = [
  ["width", "Width"],
  ["height", "Height"],
  ["depth", "Depth"],
  ["strap_drop", "Strap drop"],
  ["closure", "Closure"],
  ["compartments", "Compartments"],
  ["fits", "What fits"],
] as const;
export type BagDetailKey = (typeof bagDetailFields)[number][0];
export type BagDetails = Partial<Record<BagDetailKey, string>>;
export const BAG_DETAIL_MAX = 160;

const labelToKey = new Map<string, BagDetailKey>(
  bagDetailFields.map(([key, label]) => [label.toLowerCase(), key]),
);
const clean = (v: string) =>
  v.replace(/[\r\n]+/g, " ").trim().slice(0, BAG_DETAIL_MAX);

export function formatBagDetails(details: BagDetails): string {
  return bagDetailFields
    .map(([key, label]) => [label, clean(details[key] ?? "")] as const)
    .filter(([, value]) => value)
    .map(([label, value]) => `${label}: ${value}`)
    .join("\n");
}

// Recognised lines become details; anything else is kept as free notes.
export function parseBagDetails(text: string | null | undefined): {
  details: BagDetails;
  notes: string;
} {
  const details: BagDetails = {};
  const notes: string[] = [];
  for (const line of (text ?? "").split(/\r?\n/)) {
    const match = /^\s*([^:]{2,20}):\s*(.+?)\s*$/.exec(line);
    const key = match && labelToKey.get(match[1].trim().toLowerCase());
    if (key && !details[key]) details[key] = match![2].slice(0, BAG_DETAIL_MAX);
    else if (line.trim()) notes.push(line.trim());
  }
  return { details, notes: notes.join("\n") };
}

export function combineBagDetails(details: BagDetails, notes: string): string {
  return [formatBagDetails(details), notes.trim()].filter(Boolean).join("\n");
}

// "30 × 22 × 12 cm (W × H × D)" from whichever measurements are known.
export function bagDimensions(details: BagDetails): string | null {
  const parts = (["width", "height", "depth"] as const)
    .map((k) => [k, details[k]?.trim()] as const)
    .filter(([, v]) => v);
  if (!parts.length) return null;
  const numeric = parts.every(([, v]) => /^\d+(\.\d+)?\s*(cm)?$/i.test(v!));
  if (!numeric)
    return parts
      .map(([k, v]) => `${k[0].toUpperCase()}${k.slice(1)} ${v}`)
      .join(", ");
  const letters = parts.map(([k]) => k[0].toUpperCase()).join(" × ");
  return (
    parts.map(([, v]) => v!.replace(/\s*cm$/i, "")).join(" × ") +
    ` cm (${letters})`
  );
}
