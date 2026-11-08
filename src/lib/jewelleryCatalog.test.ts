import { describe, expect, it } from "vitest";
import {
  jewelleryCategories,
  jewellerySizes,
  jewelleryCategoryHref,
  isJewelleryCategory,
} from "../../shared/jewellery";
import { missingVariants } from "./lingerieCatalog";
import { buildImportPlan, JEWELLERY_IMPORT_TEMPLATE } from "./csvImport";

describe("jewellery catalogue", () => {
  it("recognises jewellery categories without changing clothing classification", () => {
    for (const c of jewelleryCategories)
      expect(isJewelleryCategory(" " + c.name.toUpperCase() + " ")).toBe(true);
    for (const c of ["Bras", "Nightwear", undefined, "Jewellery care"])
      expect(isJewelleryCategory(c)).toBe(false);
  });
  it("keeps ring sizing systems and length labels explicit", () => {
    expect(jewellerySizes("Rings")).toContain("US 7");
    expect(jewellerySizes("Necklaces")).toContain("45 cm");
    expect(jewellerySizes("Earrings")).toEqual(["One size"]);
  });
  it("generates separate ring size/finish stock variants and skips duplicates", () => {
    const rows = missingVariants(
      "LV-RNG",
      ["US 7", "US 8"],
      ["Gold tone", "Silver tone"],
      [],
      [],
    );
    expect(rows).toHaveLength(4);
    expect(new Set(rows.map((r) => r.sku)).size).toBe(4);
    expect(
      missingVariants(
        "LV-RNG",
        ["US 7", "US 8"],
        ["Gold tone", "Silver tone"],
        [],
        rows,
      ),
    ).toEqual([]);
  });
  it("links categories through exact catalogue filters, not ambiguous text searches", () => {
    for (const c of jewelleryCategories) {
      const url = new URL(
        jewelleryCategoryHref(c.name),
        "https://ladyvogue.pk",
      );
      expect(url.pathname).toBe("/search");
      expect(url.searchParams.get("category")).toBe(c.name);
      expect(url.searchParams.has("q")).toBe(false);
    }
  });
  it("imports earrings as a sellable item and rings as independent variants", () => {
    const plan = buildImportPlan(JEWELLERY_IMPORT_TEMPLATE, {
      skus: new Set(),
      barcodes: new Set(),
      styleCodes: new Set(),
    });
    expect(plan.errors).toEqual([]);
    expect(plan.styles).toHaveLength(2);
    expect(plan.styles[0].category).toBe("Earrings");
    expect(plan.styles[0].variants[0].openingStock).toBe(5);
    expect(plan.styles[1].variants.map((r) => r.size)).toEqual([
      "US 7",
      "US 8",
    ]);
  });
});
