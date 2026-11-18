import { expect, it } from "vitest";
import {
  dashboardRange,
  salesStats,
  dailySeries,
  dayLabels,
  paymentMix,
  type SalesDay,
} from "./dashboard";
const row = (day: string, net: number, invoices = 1): SalesDay => ({
  day,
  net_after_returns: net,
  invoices,
  cost: 0,
  discounts: 0,
  gross: 0,
  margin: 0,
  net_sales: 0,
  returns: 0,
  returns_tax: 0,
  tax: 0,
});
it("uses shop dates and equal previous periods across a year boundary", () => {
  expect(dashboardRange("7", new Date("2026-12-31T21:00:00Z"))).toEqual({
    from: "2026-12-26",
    to: "2027-01-01",
    today: "2027-01-01",
    previousFrom: "2026-12-19",
    previousTo: "2026-12-25",
    days: 7,
  });
});
it("supports month-to-date and thirty days at leap boundaries", () => {
  expect(dashboardRange("month", new Date("2028-02-29T12:00:00Z")).days).toBe(
    29,
  );
  expect(dashboardRange("30", new Date("2027-01-01T00:00:00Z")).from).toBe(
    "2026-12-03",
  );
});
it("keeps returns negative, fills missing days and avoids dividing by zero", () => {
  expect(salesStats([])).toEqual({ net: 0, invoices: 0, average: 0 });
  expect(
    salesStats([row("2026-01-01", 100, 2), row("2026-01-02", -30, 0)]).average,
  ).toBe(35);
  expect(dailySeries([row("2026-01-02", -30)], "2026-01-01", 3)).toEqual([
    0, -30, 0,
  ]);
});
it("does not turn refunds into positive payment shares", () => {
  expect(
    paymentMix([
      { method: "cash", money_in: 100 },
      { method: "card", money_in: 0 },
      { method: "digital", money_in: -5 },
    ]),
  ).toEqual([{ label: "cash", value: 100 }]);
});
it("labels each day in the period across a month end", () => {
  expect(dayLabels("2026-10-30", 4)).toEqual(["30 Oct", "31 Oct", "1 Nov", "2 Nov"]);
});
