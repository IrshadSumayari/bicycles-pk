import { describe, expect, it } from "vitest";
import { braMetadataError, lingerieValueLabel } from "../../shared/lingerie";
import { filterQuery, parseFilters } from "./helpers";
describe("lingerie search intent", () => {
  it("round trips supplier labels and all product filters through sort and pagination", () => {
    const filters = parseFilters({
      category: "Bras",
      padding: "none",
      wire: "underwired",
      coverage: "full",
      product_type: "t_shirt",
      material: "Cotton & lace",
      band: "34",
      cup: "DD",
      sizing_system: "UK / Supplier A",
      color: "Rose",
      sort: "price_asc",
    });
    expect(
      parseFilters(
        Object.fromEntries(new URLSearchParams(filterQuery(filters, 2))),
      ),
    ).toEqual({ ...filters, page: 2 });
    expect(filters.cup).toBe("DD");
    expect(lingerieValueLabel("padding", filters.padding!)).toBe("Non-padded");
  });
  it("requires explicit paired labels and a supplier system without guessing conversions", () => {
    expect(braMetadataError("34", "DD", "UK")).toBeNull();
    expect(braMetadataError("75", "E", "EU")).toBeNull();
    expect(braMetadataError("34", "", "UK")).toBeTruthy();
    expect(braMetadataError("34", "DD", "")).toBeTruthy();
    expect(braMetadataError(undefined, undefined, undefined)).toBeNull();
    expect(braMetadataError("34", "dd", "UK")).toBeTruthy();
  });
});
