import { afterEach, describe, expect, it, vi } from "vitest";
import {
  combinations,
  filterQuery,
  formatPrice,
  isProductionSite,
  jsonScript,
  parseFilters,
  productJsonLd,
  stockText,
  variantOptions,
  whatsappLink,
} from "./helpers";
import type { Product, Variant } from "./types";
const variant = (
  id: string,
  size: string,
  color: string,
  stock: Variant["stock_level"] = "in_stock",
): Variant => ({
  variant_id: id,
  size,
  color,
  fit: null,
  price: 4500,
  compare_at_price: 5000,
  stock_level: stock,
});
const variants = [
  variant("one", "S", "Blue"),
  variant("two", "M", "Blue", "out_of_stock"),
  variant("three", "L", "White", "low_stock"),
];
describe("catalog helpers", () => {
  it("parses and round-trips URL filters including literal wildcards", () => {
    const filters = parseFilters({
      q: "  50%_Blue  ",
      size: "M",
      color: "Blue",
      category: "Shirts",
      price_min: "0",
      price_max: "4500.50",
      sort: "price_desc",
      page: "3",
    });
    expect(
      parseFilters(
        Object.fromEntries(new URLSearchParams(filterQuery(filters))),
      ),
    ).toEqual(filters);
    expect(filters.q).toBe("50%_Blue");
    expect(filters.price_min).toBe(0);
  });
  it("uses safe defaults for malformed filters and pages", () => {
    expect(
      parseFilters({
        price_min: "-1",
        price_max: "Infinity",
        sort: "invalid",
        page: "NaN",
      }),
    ).toMatchObject({
      price_min: undefined,
      price_max: undefined,
      sort: "new",
      page: 1,
    });
    expect(parseFilters({ q: ["first", "second"], page: "0" })).toMatchObject({
      q: "first",
      page: 1,
    });
    expect(parseFilters({ page: "99999999999" }).page).toBe(1000000);
    expect(filterQuery(parseFilters({}))).toBe("");
    expect(filterQuery(parseFilters({ q: "shirt", page: "3" }), 1)).toBe(
      "q=shirt",
    );
  });
  it("formats prices in PKR with grouping and preserves paisa", () => {
    expect(formatPrice(4500)).toBe("PKR 4,500");
    expect(formatPrice(4500.5)).toBe("PKR 4,500.50");
    expect(formatPrice(0)).toBe("PKR 0");
  });
  it("never invents size/color combinations", () => {
    expect(combinations(variants, { size: "S", color: "White" })).toEqual([]);
    expect(
      combinations(variants, { size: "L", color: "White" })[0].variant_id,
    ).toBe("three");
    expect(variantOptions(variants, "size", { color: "Blue" })).toEqual([
      { value: "S", available: true },
      { value: "M", available: false },
    ]);
    expect(variantOptions(variants, "color", {})).toEqual([
      { value: "Blue", available: true },
      { value: "White", available: true },
    ]);
  });
  it("handles one-size products and fit-specific availability", () => {
    const one = { ...variants[0], size: null, color: null, fit: "Regular" };
    expect(combinations([one], { size: "", color: "", fit: "Slim" })).toEqual(
      [],
    );
    expect(variantOptions([one], "size", {})).toEqual([
      { value: "", available: true },
    ]);
    expect(variantOptions([], "color", {})).toEqual([]);
  });
  it.each([
    ["in_stock", "In stock"],
    ["low_stock", "Only a few left"],
    ["out_of_stock", "Out of stock"],
    ["unknown", "Out of stock"],
  ])("labels %s", (band, text) => expect(stockText(band)).toBe(text));
  it("builds JSON-LD offers from server prices and stock bands", () => {
    const product = {
      title: "Blue shirt",
      description: "Cotton",
      brand: "House",
      images: [],
      variants,
    } as unknown as Product;
    const data = productJsonLd(product, "https://shop.example/products/blue");
    expect(data["@type"]).toBe("Product");
    expect(data.brand.name).toBe("Bicycles.pk");
    expect(data.offers.map((offer) => offer.availability)).toEqual([
      "https://schema.org/InStock",
      "https://schema.org/OutOfStock",
      "https://schema.org/LimitedAvailability",
    ]);
    expect(data.offers[0]).toMatchObject({
      priceCurrency: "PKR",
      price: 4500,
      url: "https://shop.example/products/blue",
    });
    expect(
      jsonScript({ name: "</script><script>alert(1)</script>" }),
    ).not.toContain("<");
  });
  it("encodes the chosen variant, title and page URL in WhatsApp messages", () => {
    const link = whatsappLink(
      "+92 300 1234567",
      "Blue & White",
      "M",
      "Blue",
      "https://shop.example/products/blue",
      "Regular",
    );
    const url = new URL(link!);
    expect(url.hostname).toBe("wa.me");
    expect(url.pathname).toBe("/923001234567");
    expect(url.searchParams.get("text")).toContain(
      "Size: M, Color: Blue, Fit: Regular",
    );
    expect(url.searchParams.get("text")).toContain("Blue & White");
    expect(url.searchParams.get("text")).toContain(
      "https://shop.example/products/blue",
    );
    expect(whatsappLink("", "Shirt", "", "", "https://example.com")).toBeNull();
  });
});
describe("isProductionSite", () => {
  afterEach(() => vi.unstubAllEnvs());
  it("is true only for the live shop", () => {
    vi.stubEnv("NEXT_PUBLIC_SITE_URL", "https://bicycles.pk");
    expect(isProductionSite()).toBe(true);
    vi.stubEnv("NEXT_PUBLIC_SITE_URL", "https://bicycles.pk/");
    expect(isProductionSite()).toBe(true);
  });
  it("keeps staging, previews and local builds out of search", () => {
    for (const url of ["https://staging.bicycles.pk", "https://bicycles-shop-staging.vercel.app", "http://localhost:3000", ""]) {
      vi.stubEnv("NEXT_PUBLIC_SITE_URL", url);
      expect(isProductionSite()).toBe(false);
    }
  });
});
