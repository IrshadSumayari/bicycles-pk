import type { ProductGuide } from "../../shared/productGuide";

import type { Database } from "@database";
export type CatalogRow =
  Database["public"]["Functions"]["catalog_list"]["Returns"][number];
export type Collection =
  Database["public"]["Functions"]["catalog_collections"]["Returns"][number];
export type StockBand = "in_stock" | "low_stock" | "out_of_stock";
export type ProductImage = {
  storage_path: string;
  alt: string | null;
  variant_color: string | null;
};
export type Variant = {
  bra_band?: string | null;
  bra_cup?: string | null;
  variant_id: string;
  size: string | null;
  color: string | null;
  fit: string | null;
  price: number;
  compare_at_price: number | null;
  stock_level: StockBand;
};
export type Related = {
  style_id: string;
  slug: string;
  title: string;
  min_price: number;
  image_path: string | null;
};
export type Product = {
  specs?: unknown;
  bulky?: boolean;
  purchase_policy?: { cod_enabled?: boolean };
  product_guide?: ProductGuide;
  style_id: string;
  slug: string;
  title: string;
  description: string | null;
  kind: string;
  brand: string | null;
  material: string | null;
  season: string | null;
  category: string | null;
  unit: string;
  min_price: number;
  max_price: number;
  stock_level: StockBand;
  images: ProductImage[];
  variants: Variant[];
  size_chart: Database["public"]["Tables"]["size_schemes"]["Row"]["size_chart"];
  related: Related[];
};
export type Facets = {
  sizes: string[];
  colors: string[];
  price_min: number | null;
  price_max: number | null;
};
