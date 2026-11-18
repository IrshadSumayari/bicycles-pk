import { expect, it } from "vitest";
import { buildNavigation } from "./navigation";
it("uses valid collection results once, preserving their order", () => {
  expect(
    buildNavigation([
      { name: "Bras", slug: "bras" },
      { name: "Duplicate", slug: "bras" },
      { name: "Unsafe", slug: "../account" },
      { name: "Nightwear", slug: "nightwear" },
    ]),
  ).toEqual([
    { label: "Bras", href: "/collections/bras" },
    { label: "Nightwear", href: "/collections/nightwear" },
  ]);
});
it("preserves long handles up to 120 characters", () => {
  expect(
    buildNavigation([
      { name: "Long", slug: "a".repeat(120) },
      { name: "Too long", slug: "b".repeat(121) },
    ]),
  ).toHaveLength(1);
});
