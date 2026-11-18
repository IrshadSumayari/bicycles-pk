import Link from "next/link";
import { CardPhoto } from "./card-photo";
import { ArrowUpRight, Bike } from "lucide-react";
import { formatPrice, imageUrl } from "@/lib/helpers";
import type { CatalogRow, Related } from "@/lib/types";
// Listing card: product photo on a light-grey panel, bold name, a short
// options line (sizes and colours) and the price.
export function cardSubtitle(product: CatalogRow | Related): string {
  if (!("sizes" in product)) return "";
  const sizes = (product.sizes ?? []).filter(Boolean);
  const colours = (product.colors ?? []).filter(Boolean).length;
  const sizeText =
    sizes.length > 1
      ? `${sizes[0]} – ${sizes[sizes.length - 1]}`
      : sizes[0] && sizes[0] !== "One size"
        ? sizes[0]
        : "";
  const colourText = colours > 1 ? `${colours} colours` : "";
  return [sizeText, colourText].filter(Boolean).join(" · ");
}
export function ProductCard({ product }: { product: CatalogRow | Related }) {
  const src = imageUrl(product.image_path),
    compare = "compare_at_price" in product ? product.compare_at_price : null;
  const soldOut =
    "stock_level" in product && product.stock_level === "out_of_stock";
  const subtitle = cardSubtitle(product);
  return (
    <article className="lv-bike-card">
      <Link
        className="lv-bike-card-photo"
        href={`/products/${product.slug}`}
        aria-label={product.title}
      >
        {src ? (
          <CardPhoto
            path={product.image_path}
            angles={"angle_paths" in product ? product.angle_paths : null}
            alt={product.title}
          />
        ) : (
          <span className="lv-bike-card-fallback">
            <Bike size={56} strokeWidth={1} aria-hidden="true" />
          </span>
        )}
        {compare && compare > product.min_price ? (
          <span className="lv-bike-card-badge">
            -{Math.round((1 - product.min_price / compare) * 100)}%
          </span>
        ) : soldOut ? (
          <span className="lv-bike-card-badge muted">Sold out</span>
        ) : null}
        <span className="lv-bike-card-arrow" aria-hidden="true">
          <ArrowUpRight size={18} />
        </span>
      </Link>
      <h3>
        <Link href={`/products/${product.slug}`}>{product.title}</Link>
      </h3>
      {subtitle && <p className="lv-bike-card-sub">{subtitle}</p>}
      <p className="lv-bike-card-price">
        {formatPrice(product.min_price)}
        {compare && compare > product.min_price ? (
          <del>{formatPrice(compare)}</del>
        ) : null}
      </p>
    </article>
  );
}
