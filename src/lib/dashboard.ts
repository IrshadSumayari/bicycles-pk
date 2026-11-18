import type { Database } from "./database.types";
export type SalesDay =
  Database["public"]["Functions"]["report_sales_summary"]["Returns"][number];
const day = (d: Date) => d.toISOString().slice(0, 10),
  shift = (value: string, n: number) => {
    const d = new Date(value + "T00:00:00Z");
    d.setUTCDate(d.getUTCDate() + n);
    return day(d);
  };
export function dashboardRange(period: "7" | "30" | "month", now: Date) {
  const today = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Karachi",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(now);
  const from =
    period === "month"
      ? today.slice(0, 8) + "01"
      : shift(today, period === "7" ? -6 : -29);
  const days =
    Math.round((Date.parse(today) - Date.parse(from)) / 86400000) + 1;
  return {
    from,
    to: today,
    previousFrom: shift(from, -days),
    previousTo: shift(from, -1),
    days,
    today,
  };
}
export function salesStats(rows: SalesDay[]) {
  const net = rows.reduce((n, r) => n + r.net_after_returns, 0),
    invoices = rows.reduce((n, r) => n + r.invoices, 0);
  return { net, invoices, average: invoices ? net / invoices : 0 };
}
// Short chart labels ("15 Oct") for each shop day in the period.
export function dayLabels(from: string, days: number) {
  const format = new Intl.DateTimeFormat("en-GB", { day: "numeric", month: "short", timeZone: "UTC" });
  return Array.from({ length: days }, (_, i) =>
    format.format(new Date(shift(from, i) + "T00:00:00Z")),
  );
}
export function dailySeries(rows: SalesDay[], from: string, days: number) {
  const values = new Map(rows.map((r) => [r.day, r.net_after_returns]));
  return Array.from(
    { length: days },
    (_, i) => values.get(shift(from, i)) ?? 0,
  );
}
export function paymentMix(rows: { method: string; money_in: number }[]) {
  return rows
    .filter((r) => r.money_in > 0)
    .map((r) => ({ label: r.method, value: r.money_in }));
}
