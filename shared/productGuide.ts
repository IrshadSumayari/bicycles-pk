export const measurementKeys = ["underbust", "bust", "waist", "hips"] as const;
export type MeasurementKey = (typeof measurementKeys)[number];
export type ChartRow = { size: string } & Partial<
  Record<MeasurementKey, string>
>;
export type SupplierChart = {
  unit: "cm" | "in";
  basis: "body" | "garment";
  source: string;
  rows: ChartRow[];
};
export type ProductGuide = {
  fit?: string;
  care?: string;
  included?: string;
  size_chart?: SupplierChart;
};
export const measurementLabels: Record<MeasurementKey, string> = {
  underbust: "Underbust",
  bust: "Bust",
  waist: "Waist",
  hips: "Hips",
};
const object = (v: unknown): v is Record<string, unknown> =>
  !!v && typeof v === "object" && !Array.isArray(v);
export function productGuideError(value: unknown): string | null {
  if (
    !object(value) ||
    Object.keys(value).some(
      (k) => !["fit", "care", "included", "size_chart"].includes(k),
    )
  )
    return "Use only fit, care, included items and a supplier chart.";
  for (const k of ["fit", "care", "included"])
    if (k in value && (typeof value[k] !== "string" || value[k].length > 2000))
      return "Product information must be text of at most 2,000 characters.";
  if (!("size_chart" in value)) return null;
  const c = value.size_chart;
  if (
    !object(c) ||
    Object.keys(c).some(
      (k) => !["unit", "basis", "source", "rows"].includes(k),
    ) ||
    typeof c.unit !== "string" ||
    !["cm", "in"].includes(c.unit) ||
    typeof c.basis !== "string" ||
    !["body", "garment"].includes(c.basis) ||
    typeof c.source !== "string" ||
    !c.source.trim() ||
    c.source.length > 160 ||
    !Array.isArray(c.rows) ||
    c.rows.length < 1 ||
    c.rows.length > 30
  )
    return "Choose the chart unit, measurement basis and supplier source, and add 1–30 rows.";
  const sizes = new Set<string>();
  for (const r of c.rows) {
    if (
      !object(r) ||
      Object.keys(r).some((k) => !["size", ...measurementKeys].includes(k)) ||
      Object.values(r).some((v) => typeof v !== "string" || v.length > 60) ||
      typeof r.size !== "string" ||
      !r.size.trim() ||
      !measurementKeys.some((k) => typeof r[k] === "string" && r[k].trim())
    )
      return "Each chart row needs a size and at least one measurement, with cells up to 60 characters.";
    const size = r.size.trim().toLowerCase();
    if (sizes.has(size)) return "List each chart size once.";
    sizes.add(size);
  }
  return null;
}
export function readProductGuide(value: unknown): ProductGuide {
  return productGuideError(value) === null ? (value as ProductGuide) : {};
}
