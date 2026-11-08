import { describe, expect, it } from "vitest";
import {
  braSizes,
  missingVariants,
  duplicateVariantError,
} from "./lingerieCatalog";

describe("LadyVogue variants", () => {
  it("keeps supplier cup labels distinct and removes repeated choices", () => {
    expect(braSizes(["34", " 34 ", "36"], ["DD", "dd", "E"])).toEqual([
      "34DD",
      "34E",
      "36DD",
      "36E",
    ]);
  });
  it("creates one SKU per size and color and skips existing variants", () => {
    const rows = missingVariants(
      "LV1",
      ["34B", "34b", "36B"],
      ["Rose", "rose", "Ivory"],
      [],
      [{ sku: "OLD", size: "34B", color: "Rose" }],
    );
    expect(rows).toHaveLength(3);
    expect(rows.map((r) => r.sku)).toEqual([
      "LV1-ROSE-36B",
      "LV1-IVOR-34B",
      "LV1-IVOR-36B",
    ]);
  });
  it("assigns unique SKUs when long supplier sizes truncate identically", () => {
    const rows = missingVariants("LV1", ["32DDD", "32DDG"], ["Rose"], [], []);
    expect(rows.map((r) => r.sku)).toEqual([
      "LV1-ROSE-32DD",
      "LV1-ROSE-32DD-2",
    ]);
    expect(
      missingVariants("LV1", ["32DDD", "32DDG"], ["Rose"], [], rows),
    ).toEqual([]);
  });
  it("keeps unsized products supported", () => {
    expect(missingVariants("ROBE", [], [], [], [])).toEqual([
      { sku: "ROBE", size: undefined, color: undefined, fit: undefined },
    ]);
  });
  it("rejects duplicate manually edited sizes and identifiers", () => {
    expect(
      duplicateVariantError([
        { sku: "A", size: "34B" },
        { sku: "B", size: " 34b " },
      ]),
    ).toContain("combination");
    expect(
      duplicateVariantError([
        { sku: "A", size: "M" },
        { sku: "a ", size: "L" },
      ]),
    ).toContain("SKU");
    expect(
      duplicateVariantError([
        { sku: "A", size: "M", barcode: "123" },
        { sku: "B", size: "L", barcode: "123" },
      ]),
    ).toContain("Barcode");
  });
  it("accepts distinct cups without changing existing stock fields", () => {
    const existing = [{ sku: "A", size: "34DD", stock: 9 }];
    expect(
      missingVariants("LV1", ["34DD", "34E"], [], [], existing).map(
        (r) => r.size,
      ),
    ).toEqual(["34E"]);
    expect(existing[0].stock).toBe(9);
    expect(
      duplicateVariantError([
        { sku: "A", size: "34DD" },
        { sku: "B", size: "34E" },
      ]),
    ).toBeUndefined();
  });
});

describe("lingerie kind and set sizes", () => {
  it("reads the kind from the category", async () => {
    const { lingerieKind } = await import("./lingerieCatalog");
    expect(lingerieKind("Bras")).toBe("bra");
    expect(lingerieKind("Lingerie Sets")).toBe("set");
    expect(lingerieKind("Panties")).toBe("bottom");
    expect(lingerieKind("Nightwear")).toBe("apparel");
    expect(lingerieKind("Robes")).toBe("apparel");
    expect(lingerieKind("Kurtas", "Lace bra")).toBeNull();
  });
  it("uses the name while no category is chosen, and spots a pair in a bra category", async () => {
    const { lingerieKind } = await import("./lingerieCatalog");
    expect(lingerieKind("", "")).toBeNull();
    expect(lingerieKind("", "Lace Bra")).toBe("bra");
    expect(lingerieKind("", "Bracelet")).toBeNull();
    expect(lingerieKind("Bras", "Everyday Use BRA & PENTIES Pair")).toBe("set");
    expect(lingerieKind("", "Satin pyjama set")).toBe("apparel");
  });
  it("pairs every bra size with every panty size", async () => {
    const { setSizes } = await import("./lingerieCatalog");
    expect(setSizes(["34B", "36B"], ["M", "L", "m"])).toEqual([
      "34B / M", "34B / L", "36B / M", "36B / L",
    ]);
    expect(setSizes([], ["S", "M"])).toEqual(["S", "M"]);
    expect(setSizes(["34B"], [])).toEqual(["34B"]);
  });
});
