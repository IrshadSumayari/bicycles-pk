import { describe, expect, it } from "vitest";
import pages from "../content/pages/index.json";
import { buildShopMenus, legalLinks, supportLinks } from "./shop-navigation";
import { categoryHref } from "./ladyvogue";

describe("shopping navigation contracts", () => {
  it("uses exact stored categories when collections are unavailable", () => {
    for (const [slug, label] of [
      ["bras", "Bras"],
      ["panties", "Panties"],
      ["nightwear", "Nightwear"],
      ["matching-sets", "Lingerie Sets"],
    ]) {
      const url = new URL(
        categoryHref(slug, "ignored keyword", []),
        "https://ladyvogue.pk",
      );
      expect(url.searchParams.get("category")).toBe(label);
      expect(url.searchParams.has("q")).toBe(false);
    }
  });
  it("prefers existing collections and exposes only supplied specialist collections", () => {
    const menus = buildShopMenus([{ slug: "bras" }, { slug: "wireless-bras" }]);
    const bras = menus.find((m) => m.label === "Bras")!;
    expect(bras.href).toBe("/collections/bras");
    expect(bras.children).toContainEqual({
      label: "Wireless bras",
      href: "/collections/wireless-bras",
    });
    expect(bras.children.some((c) => c.label === "Wired bras")).toBe(false);
    expect(
      buildShopMenus([])
        .flatMap((m) => m.children)
        .some((c) => c.href.includes("wireless")),
    ).toBe(false);
  });
  it("every published help/legal page link resolves to an existing content entry", () => {
    for (const link of [...supportLinks, ...legalLinks]) {
      if (["/account/orders","/account/track"].includes(link.href)) continue;
      const [, kind, handle] = link.href.split("/");
      expect(
        pages.some((page) => page.kind === kind && page.handle === handle),
        link.href,
      ).toBe(true);
    }
  });
  it("jewellery links preserve canonical category names, including sets", () => {
    const children = buildShopMenus([]).find(
      (m) => m.label === "Jewellery",
    )!.children;
    expect(children.find((c) => c.label === "Jewellery Sets")?.href).toBe(
      "/search?category=Jewellery%20Sets",
    );
    expect(new Set(children.map((c) => c.href)).size).toBe(children.length);
  });
  it("bag links preserve canonical category names", () => {
    const menu = buildShopMenus([]).find((m) => m.label === "Bags")!;
    expect(menu.href).toBe("/bags");
    expect(menu.children.find((c) => c.label === "Wallets & Purses")?.href).toBe(
      "/search?category=Wallets%20%26%20Purses",
    );
    expect(menu.children.some((c) => c.label === "Bags")).toBe(false);
  });
});
