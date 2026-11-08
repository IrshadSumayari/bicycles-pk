import { describe, expect, it } from "vitest";
import {
  bagCategories,
  bagCategoryHref,
  bagDimensions,
  bagSizes,
  combineBagDetails,
  formatBagDetails,
  isBagCategory,
  parseBagDetails,
} from "../../shared/bags";
import { isJewelleryCategory } from "../../shared/jewellery";
import { productGuideError } from "../../shared/productGuide";
import { buildImportPlan, BAGS_IMPORT_TEMPLATE } from "./csvImport";
import { ALL_BAGS, inventoryCategoryFilter, inventoryCategoryOptions } from "./inventoryCategory";

describe("bags catalogue", () => {
  it("recognises bag categories only, separately from jewellery and lingerie", () => {
    for (const c of bagCategories) {
      expect(isBagCategory(" " + c.name.toUpperCase() + " ")).toBe(true);
      expect(isJewelleryCategory(c.name)).toBe(false);
    }
    for (const c of ["Bras", "Rings", "Shopping bag", undefined, null])
      expect(isBagCategory(c)).toBe(false);
  });
  it("offers size shortcuts per shape", () => {
    expect(bagSizes("Tote Bags")).toContain("Large");
    expect(bagSizes("Mini Bags")).toContain("Mini");
    expect(bagSizes("Unknown")).toEqual([]);
  });
  it("links shapes through exact category filters, including ampersands", () => {
    for (const c of bagCategories) {
      const url = new URL(bagCategoryHref(c.name), "https://ladyvogue.pk");
      expect(url.pathname).toBe("/search");
      expect(url.searchParams.get("category")).toBe(c.name);
    }
  });
  it("round-trips bag details through the product guide fit text", () => {
    const text = combineBagDetails(
      { width: "30 cm", height: "22", depth: "12 cm", strap_drop: "55 cm, adjustable", closure: "Zip" },
      "Gold-tone hardware",
    );
    expect(text).toBe(
      "Width: 30 cm\nHeight: 22\nDepth: 12 cm\nStrap drop: 55 cm, adjustable\nClosure: Zip\nGold-tone hardware",
    );
    expect(productGuideError({ fit: text })).toBeNull();
    const parsed = parseBagDetails(text);
    expect(parsed.details.strap_drop).toBe("55 cm, adjustable");
    expect(parsed.notes).toBe("Gold-tone hardware");
    expect(formatBagDetails({ fits: "Phone\nwallet", closure: "  " })).toBe("What fits: Phone wallet");
  });
  it("keeps unrecognised or older free-text notes as notes", () => {
    const parsed = parseBagDetails("Note: handle with care\nFits a 13 inch laptop");
    expect(parsed.details).toEqual({});
    expect(parsed.notes).toBe("Note: handle with care\nFits a 13 inch laptop");
  });
  it("formats dimensions for shoppers", () => {
    expect(bagDimensions({ width: "30 cm", height: "22", depth: "12" })).toBe("30 × 22 × 12 cm (W × H × D)");
    expect(bagDimensions({ width: "30", height: "22" })).toBe("30 × 22 cm (W × H)");
    expect(bagDimensions({ width: "12 in" })).toBe("Width 12 in");
    expect(bagDimensions({})).toBeNull();
  });
  it("starts the Bags section on every bag category", () => {
    const options = inventoryCategoryOptions("bags", ["Bras"]);
    expect(options[0]).toBe(ALL_BAGS);
    expect(options).toContain("Wallets & Purses");
    expect(options).not.toContain("Bras");
    expect(inventoryCategoryFilter(ALL_BAGS)).toEqual({ categories: bagCategories.map((c) => c.name) });
    expect(inventoryCategoryFilter("Clutches")).toEqual({ category: "Clutches" });
  });
  it("imports the bag examples as sellable styles with size/colour variants", () => {
    const plan = buildImportPlan(BAGS_IMPORT_TEMPLATE, { skus: new Set(), barcodes: new Set(), styleCodes: new Set() });
    expect(plan.errors).toEqual([]);
    expect(plan.styles.map((s) => s.category)).toEqual(["Tote Bags", "Crossbody Bags", "Wallets & Purses"]);
    expect(plan.styles[0].variants.map((v) => v.color)).toEqual(["Black", "Tan"]);
    expect(plan.styles[1].variants[0].fit).toBe("Chain strap");
  });
});

describe('new styles from a department', () => {
  it('start in the chosen bag shape, or Bags under All bags', async () => {
    const { newStyleCategory, departmentCategories } = await import('./inventoryCategory')
    expect(newStyleCategory('bags', 'Tote Bags')).toBe('Tote Bags')
    expect(newStyleCategory('bags', 'All bags')).toBe('Bags')
    expect(newStyleCategory('jewellery', 'All jewellery')).toBe('Jewellery')
    expect(newStyleCategory(undefined, 'All')).toBeUndefined()
    expect(departmentCategories('bags')).not.toContain('LV bags')
  })
})
