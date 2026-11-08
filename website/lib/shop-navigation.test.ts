import { describe, expect, it } from "vitest";
import pages from "../content/pages/index.json";
import { buildShopMenus, legalLinks, supportLinks } from "./shop-navigation";
import { shopSections } from "../../shared/bicycles";

describe("shopping navigation contracts", () => {
  it("has one menu per shop section plus help", () => {
    const menus = buildShopMenus([]);
    expect(menus.map((m) => m.label)).toEqual([...shopSections.map((s) => s.label), "Help"]);
    expect(menus.find((m) => m.label === "Kids")!.href).toBe("/kids");
  });
  it("links categories by their exact stored names, without the general category", () => {
    const menu = buildShopMenus([]).find((m) => m.label === "Accessories")!;
    expect(menu.children.find((c) => c.label === "Bottles & Cages")?.href).toBe(
      "/search?category=Bottles%20%26%20Cages",
    );
    expect(menu.children.some((c) => c.label === "Accessories")).toBe(false);
    const hrefs = buildShopMenus([]).flatMap((m) => m.children.map((c) => c.href));
    expect(new Set(hrefs).size).toBe(hrefs.length);
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
});
