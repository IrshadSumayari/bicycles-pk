export const jewelleryCategories = [
  {
    name: "Jewellery",
    slug: "jewellery",
    description: "Little details for every day.",
    sizes: ["One size", "Adjustable"],
  },
  {
    name: "Earrings",
    slug: "earrings",
    description: "From quiet sparkle to a statement pair.",
    sizes: ["One size"],
  },
  {
    name: "Necklaces",
    slug: "necklaces",
    description: "A finishing touch, close to your heart.",
    sizes: ["40 cm", "45 cm", "50 cm", "Adjustable"],
  },
  {
    name: "Rings",
    slug: "rings",
    description: "Your own little signature.",
    sizes: ["US 5", "US 6", "US 7", "US 8", "US 9", "US 10", "Adjustable"],
  },
  {
    name: "Bracelets",
    slug: "bracelets",
    description: "Something lovely at your wrist.",
    sizes: ["One size", "Adjustable"],
  },
  {
    name: "Bangles",
    slug: "bangles",
    description: "Made for a little everyday movement.",
    sizes: ["One size", "Adjustable"],
  },
  {
    name: "Anklets",
    slug: "anklets",
    description: "A delicate detail of your own.",
    sizes: ["One size", "Adjustable"],
  },
  {
    name: "Jewellery Sets",
    slug: "jewellery-sets",
    description: "Beautiful pieces, brought together.",
    sizes: ["One size"],
  },
] as const;
export const jewelleryFinishes = [
  "Gold tone",
  "Silver tone",
  "Rose gold tone",
  "Oxidised",
  "Multicolour",
];
export function isJewelleryCategory(category: string | undefined): boolean {
  const value = category?.trim().toLowerCase();
  return jewelleryCategories.some((c) => c.name.toLowerCase() === value);
}
export function jewellerySizes(category: string): readonly string[] {
  return (
    jewelleryCategories.find(
      (c) => c.name.toLowerCase() === category.trim().toLowerCase(),
    )?.sizes ?? []
  );
}
export function jewelleryCategoryHref(category: string): string {
  return "/search?category=" + encodeURIComponent(category);
}
