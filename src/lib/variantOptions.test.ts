import { describe, expect, it } from "vitest";
import { missingVariants, duplicateVariantError, uniqueOptions } from "./variantOptions";

describe("style variants", () => {
  it("removes repeated choices regardless of case and spacing", () => {
    expect(uniqueOptions(["M", " m ", "L", ""])).toEqual(["M", "L"]);
  });
  it("creates one SKU per size and colour and skips existing variants", () => {
    const rows = missingVariants(
      "BK1",
      ["M", "m", "L"],
      ["Red", "red", "Blue"],
      [],
      [{ sku: "OLD", size: "M", color: "Red" }],
    );
    expect(rows).toHaveLength(3);
    expect(rows.map((r) => r.sku)).toEqual(["BK1-RED-L", "BK1-BLUE-M", "BK1-BLUE-L"]);
  });
  it("assigns unique SKUs when long sizes truncate identically", () => {
    const rows = missingVariants("BK1", ["27.5A", "27.5B"], ["Red"], [], []);
    expect(new Set(rows.map((r) => r.sku)).size).toBe(2);
    expect(missingVariants("BK1", ["27.5A", "27.5B"], ["Red"], [], rows)).toEqual([]);
  });
  it("keeps unsized products supported", () => {
    expect(missingVariants("LOCK", [], [], [], [])).toEqual([
      { sku: "LOCK", size: undefined, color: undefined, fit: undefined },
    ]);
  });
  it("rejects duplicate manually edited sizes and identifiers", () => {
    expect(duplicateVariantError([{ sku: "A", size: "M" }, { sku: "B", size: " m " }])).toContain("combination");
    expect(duplicateVariantError([{ sku: "A", size: "M" }, { sku: "a ", size: "L" }])).toContain("SKU");
    expect(
      duplicateVariantError([
        { sku: "A", size: "M", barcode: "123" },
        { sku: "B", size: "L", barcode: "123" },
      ]),
    ).toContain("Barcode");
    expect(duplicateVariantError([{ sku: "A", size: '16"' }, { sku: "B", size: '20"' }])).toBeUndefined();
  });
});
