import { shopSections } from "../../shared/bicycles";
import { brand } from "./brand";
import type { Product, StockBand, Variant } from "./types";
export type Filters = {
  q: string;
  size: string;
  color: string;
  category: string;
  section: string;
  price_min?: number;
  price_max?: number;
  sort: "new" | "price_asc" | "price_desc";
  page: number;
};
export type Query = Record<string, string | string[] | undefined>;
export function parseFilters(query: Query): Filters {
  const value = (key: string) => {
    const raw = query[key];
    return (Array.isArray(raw) ? raw[0] : raw)?.trim() ?? "";
  };
  const price = (key: string) =>
    /^\d+(\.\d{1,2})?$/.test(value(key)) && Number.isFinite(Number(value(key)))
      ? Number(value(key))
      : undefined;
  const sort = value("sort");
  return {
    q: value("q"),
    size: value("size"),
    color: value("color"),
    category: value("category"),
    section: shopSections.some((x) => x.id === value("section")) ? value("section") : "",
    price_min: price("price_min"),
    price_max: price("price_max"),
    sort: sort === "price_asc" || sort === "price_desc" ? sort : "new",
    page: /^\d+$/.test(value("page"))
      ? Math.min(1000000, Math.max(1, Number(value("page"))))
      : 1,
  };
}
export function filterQuery(filters: Filters, page = filters.page): string {
  const query = new URLSearchParams();
  for (const key of [
    "q",
    "size",
    "color",
    "category",
    "section",
    "price_min",
    "price_max",
  ] as const)
    if (filters[key] !== "" && filters[key] !== undefined)
      query.set(key, String(filters[key]));
  if (filters.sort !== "new") query.set("sort", filters.sort);
  if (page > 1) query.set("page", String(page));
  return query.toString();
}
export function formatPrice(value: number): string {
  return (
    "PKR " +
    new Intl.NumberFormat("en-PK", {
      minimumFractionDigits: Number.isInteger(value) ? 0 : 2,
      maximumFractionDigits: 2,
    }).format(value)
  );
}
export function stockText(band: string): string {
  return band === "in_stock"
    ? "In stock"
    : band === "low_stock"
      ? "Only a few left"
      : "Out of stock";
}
export function combinations(
  variants: Variant[],
  selected: { size?: string; color?: string; fit?: string } = {},
) {
  return variants.filter(
    (v) =>
      (selected.size === undefined || (v.size ?? "") === selected.size) &&
      (selected.color === undefined || (v.color ?? "") === selected.color) &&
      (selected.fit === undefined || (v.fit ?? "") === selected.fit),
  );
}
export function variantOptions(
  variants: Variant[],
  dimension: "size" | "color" | "fit",
  selected: { size?: string; color?: string; fit?: string },
) {
  const others = { ...selected };
  delete others[dimension];
  const matches = combinations(variants, others);
  return [...new Set(matches.map((v) => v[dimension] ?? ""))].map((value) => ({
    value,
    available: matches.some(
      (v) => (v[dimension] ?? "") === value && v.stock_level !== "out_of_stock",
    ),
  }));
}
export function imageUrl(path: string | null | undefined): string | null {
  if (!path) return null;
  const base = process.env.NEXT_PUBLIC_SUPABASE_URL;
  return base
    ? `${base.replace(/\/$/, "")}/storage/v1/object/public/product-images/${path.split("/").map(encodeURIComponent).join("/")}`
    : null;
}
export function siteUrl(path = "/"): string {
  return new URL(
    path,
    process.env.NEXT_PUBLIC_SITE_URL || "http://localhost:3000",
  ).toString();
}
export function whatsappLink(
  number: string,
  title: string,
  size: string,
  color: string,
  url: string,
  fit = "",
): string | null {
  const digits = number.replace(/\D/g, "");
  if (!/^[1-9]\d{7,14}$/.test(digits)) return null;
  const selection = [
    size && `Size: ${size}`,
    color && `Color: ${color}`,
    fit && `Fit: ${fit}`,
  ]
    .filter(Boolean)
    .join(", ");
  return `https://wa.me/${digits}?${new URLSearchParams({ text: `Hello, I would like to order ${title}${selection ? ` (${selection})` : ""}.\n${url}` })}`;
}
export function productJsonLd(product: Product, url: string) {
  const availability: Record<StockBand, string> = {
    in_stock: "https://schema.org/InStock",
    low_stock: "https://schema.org/LimitedAvailability",
    out_of_stock: "https://schema.org/OutOfStock",
  };
  return {
    "@context": "https://schema.org",
    "@type": "Product",
    name: product.title,
    description: product.description ?? undefined,
    image: product.images
      .map((image) => imageUrl(image.storage_path))
      .filter(Boolean),
    brand: { "@type": "Brand", name: brand.name },
    offers: product.variants.map((variant) => ({
      "@type": "Offer",
      priceCurrency: "PKR",
      price: variant.price,
      availability: availability[variant.stock_level],
      url,
    })),
  };
}
export function jsonScript(value: unknown): string {
  return JSON.stringify(value).replace(/</g, "\\u003c");
}
