import { beforeEach, describe, expect, it, vi } from "vitest";
const db = vi.hoisted(() => ({ rpc: vi.fn() }));
vi.mock("./supabase", () => ({ supabase: db }));
import { stylesService, type StyleInput } from "./services";
const base: StyleInput = {
  styleId: "existing-style",
  kind: "garment",
  code: "LV-BRA",
  name: "Bra",
  taxable: true,
  active: true,
  trackInventory: true,
  variants: [
    {
      variantId: "existing-variant",
      sku: "LV-BRA-34DD",
      size: "34DD",
      price: 100,
      active: true,
    },
  ],
};
beforeEach(() => {
  vi.clearAllMocks();
  db.rpc.mockResolvedValue({ data: "existing-style", error: null });
});
describe("lingerie style save contract", () => {
  it("preserves variant identity and avoids stock replacement while saving supplier labels", async () => {
    expect(
      await stylesService.save({
        ...base,
        lingerie: { padding: "none", sizing_system: "UK" },
        variants: [
          {
            ...base.variants[0],
            braBand: "34",
            braCup: "DD",
            openingStock: 99,
          },
        ],
      }),
    ).toBe("existing-style");
    const p = db.rpc.mock.calls[0][1].p;
    expect(p.lingerie).toEqual({ padding: "none", sizing_system: "UK" });
    expect(p.variants[0]).toMatchObject({
      variant_id: "existing-variant",
      bra_band: "34",
      bra_cup: "DD",
      opening_stock: null,
    });
  });
  it("omits metadata keys for legacy imports instead of clearing saved values", async () => {
    await stylesService.save(base);
    const p = db.rpc.mock.calls[0][1].p;
    expect(p).not.toHaveProperty("lingerie");
    expect(p.variants[0]).not.toHaveProperty("bra_band");
    expect(p.variants[0]).not.toHaveProperty("bra_cup");
  });
});
