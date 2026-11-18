import { describe, it, expect } from "vitest";
import { cartReducer, readCart } from "./cart";
const variant_id = "00000000-0000-4000-8000-000000000001";
describe("bag", () => {
  it("adds, merges, and clamps to ten", () => {
    const first = cartReducer([], { type: "add", variant_id, quantity: 2 });
    expect(first).toEqual([{ variant_id, quantity: 2 }]);
    expect(
      cartReducer(first, { type: "add", variant_id, quantity: 9 }),
    ).toEqual([{ variant_id, quantity: 10 }]);
  });
  it("sets quantity and removes lines", () => {
    const lines = [{ variant_id, quantity: 2 }];
    expect(
      cartReducer(lines, { type: "set", variant_id, quantity: 3 })[0].quantity,
    ).toBe(3);
    expect(cartReducer(lines, { type: "remove", variant_id })).toEqual([]);
    expect(cartReducer(lines, { type: "clear" })).toEqual([]);
  });
  it("rejects invalid quantities and references", () => {
    for (const quantity of [0, -1, NaN, 1.5])
      expect(cartReducer([], { type: "add", variant_id, quantity })).toEqual(
        [],
      );
    expect(
      cartReducer([], { type: "add", variant_id: "bad", quantity: 1 }),
    ).toEqual([]);
  });
  it("loads only versioned intent, strips prices, ignores older bags, and survives corrupt storage", () => {
    expect(
      readCart(
        JSON.stringify({
          version: 3,
          lines: [{ variant_id, quantity: 2, price: 1 }],
        }),
      ),
    ).toEqual([{ variant_id, quantity: 2 }]);
    expect(readCart("bad")).toEqual([]);
    expect(readCart('{"version":2,"lines":[]}')).toEqual([]);
  });
});

