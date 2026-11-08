import { describe, expect, it } from "vitest";
import {
  lineRefund,
  returnSelectionErrors,
  exchangeReadiness,
} from "./returns";

describe("lineRefund", () => {
  it("refunds the paid share, not the shelf price", () => {
    expect(lineRefund(2970, 3, 0, 1)).toBe(990);
  });

  it("one-by-one returns add up exactly to the line total", () => {
    const total = 1000;
    const parts = [
      lineRefund(total, 3, 0, 1),
      lineRefund(total, 3, 1, 1),
      lineRefund(total, 3, 2, 1),
    ];
    expect(parts).toEqual([333.33, 333.34, 333.33]);
    expect(parts.reduce((a, b) => a + b, 0)).toBeCloseTo(1000, 10);
  });

  it("returns nothing for zero quantities", () => {
    expect(lineRefund(1000, 2, 0, 0)).toBe(0);
  });
});

describe("return inspection and exchange readiness", () => {
  const line = {
    description: "Lace bra 34B",
    quantity: 2,
    returned: 1,
    unit: "piece",
    qty: "1",
    condition: "",
  };
  it("requires explicit inspection before returning stock", () => {
    expect(returnSelectionErrors([line])).toEqual([
      "Inspect Lace bra 34B and choose its condition",
    ]);
    for (const condition of ["resaleable", "damaged", "faulty"])
      expect(returnSelectionErrors([{ ...line, condition }])).toEqual([]);
  });
  it("ignores unselected lines but rejects excess and fractional pieces", () => {
    expect(returnSelectionErrors([{ ...line, qty: "" }])).toEqual([]);
    expect(
      returnSelectionErrors([
        { ...line, qty: "2", condition: "resaleable" },
      ])[0],
    ).toContain("Only 1");
    expect(
      returnSelectionErrors([{ ...line, qty: "0.5", condition: "faulty" }])[0],
    ).toContain("Whole quantities");
  });
  it.each(["-1", "NaN", "Infinity"])(
    "rejects invalid return quantity %s",
    (qty) => {
      expect(returnSelectionErrors([{ ...line, qty }])[0]).toContain(
        "valid return quantity",
      );
    },
  );
  const items = [{ description: "Lace bra 36B", qty: "1", unit: "piece" }];
  it("blocks exchanges until a successful current quote is ready", () => {
    for (const quote of [
      { available: false, fetching: true, error: false },
      { available: true, fetching: true, error: false },
      { available: true, fetching: false, error: true },
    ])
      expect(exchangeReadiness(items, quote)).toHaveLength(1);
    expect(
      exchangeReadiness(items, {
        available: true,
        fetching: false,
        error: false,
      }),
    ).toEqual([]);
  });
  it("does not silently drop invalid replacement rows", () => {
    for (const qty of ["", "0", "-2", "Infinity", "1.5"])
      expect(
        exchangeReadiness([{ ...items[0], qty }], {
          available: true,
          fetching: false,
          error: false,
        })[0],
      ).toContain("replacement quantity");
  });
});
