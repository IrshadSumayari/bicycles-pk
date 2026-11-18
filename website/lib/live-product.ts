import type { Product, Variant } from "./types";
// Reads the latest product (prices and stock) straight from the catalog from
// the browser, bypassing the page cache.
export async function fetchLiveProduct(
  slug: string,
  signal?: AbortSignal,
): Promise<Product | null> {
  const base = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!base || !key) throw new Error("Unavailable");
  const response = await fetch(
    `${base.replace(/\/$/, "")}/rest/v1/rpc/catalog_product`,
    {
      method: "POST",
      headers: { apikey: key, "Content-Type": "application/json" },
      body: JSON.stringify({ p_slug: slug }),
      cache: "no-store",
      signal,
    },
  );
  if (!response.ok) throw new Error("Unavailable");
  return response.json();
}
// The one variant a quick-add can pick without asking: only when exactly one
// variant is in stock.
export function onlyInStockVariant(product: Product | null): Variant | null {
  const inStock = (product?.variants ?? []).filter(
    (v) => v.stock_level !== "out_of_stock",
  );
  return inStock.length === 1 ? inStock[0] : null;
}
