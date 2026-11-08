import "server-only";
import { cache } from "react";
import type { Database } from "@database";
import type { CatalogRow, Collection, Facets, Product } from "./types";
type Functions = Database["public"]["Functions"];
type PublicRpc =
  | "catalog_list"
  | "catalog_product"
  | "catalog_collections"
  | "catalog_facets"
  | "catalog_policy";
async function rpc<Name extends PublicRpc>(
  name: Name,
  args: Functions[Name]["Args"],
): Promise<Functions[Name]["Returns"]> {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !key) throw new Error("Catalog connection is not configured");
  const response = await fetch(
    `${url.replace(/\/$/, "")}/rest/v1/rpc/${name}`,
    {
      method: "POST",
      headers: { apikey: key, "Content-Type": "application/json" },
      body: JSON.stringify(args),
      next: { revalidate: 60 },
      signal: AbortSignal.timeout(5000),
    },
  );
  if (!response.ok) throw new Error("The catalog is temporarily unavailable");
  return response.json();
}
export const catalog = {
  policy: cache(
    async (): Promise<{ return_window_days: number }> =>
      (await rpc("catalog_policy", {})) as { return_window_days: number },
  ),
  list: (p: Functions["catalog_list"]["Args"]["p"]): Promise<CatalogRow[]> =>
    rpc("catalog_list", { p }),
  product: cache(
    async (slug: string): Promise<Product | null> =>
      (await rpc("catalog_product", {
        p_slug: slug,
      })) as unknown as Product | null,
  ),
  collections: cache(async (): Promise<Collection[]> =>
    rpc("catalog_collections", {}),
  ),
  facets: async (collection: string | null): Promise<Facets> =>
    (await rpc("catalog_facets", {
      p_collection: collection as string,
    })) as unknown as Facets,
};
export async function safeCatalog<T>(
  read: () => Promise<T>,
  fallback: T,
): Promise<T> {
  try {
    return await read();
  } catch {
    console.warn("Catalog unavailable; a later request will retry.");
    return fallback;
  }
}
