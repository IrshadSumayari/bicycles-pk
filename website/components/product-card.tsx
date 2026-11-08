import Link from "next/link";
import { CardPhoto } from "./card-photo";
import { ArrowUpRight, ShoppingBag, ImageIcon } from "lucide-react";
import { formatPrice, imageUrl } from "@/lib/helpers";
import type { CatalogRow, Related } from "@/lib/types";
import { Badge } from "./ui/badge";
import { Card } from "./ui/card";
export function ProductCard({ product }: { product: CatalogRow | Related }) {
  const src = imageUrl(product.image_path),
    compare = "compare_at_price" in product ? product.compare_at_price : null;
  return (
    <Card className="product-card p-0" role="article">
      <Link
        className="product-photo"
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
          <span className="photo-fallback">
            <ImageIcon aria-hidden="true" />
          </span>
        )}
        {compare && compare > product.min_price ? (
          <Badge className="product-badge" variant="lightPrimary">
            -{Math.round((1 - product.min_price / compare) * 100)}%
          </Badge>
        ) : null}
        {"stock_level" in product && product.stock_level === "out_of_stock" && (
          <Badge className="product-badge sold" variant="muted">
            Sold out
          </Badge>
        )}
        <span className="quick-shop">
          <ShoppingBag size={16} /> Choose options <ArrowUpRight size={16} />
        </span>
      </Link>
      <h3>
        <Link href={`/products/${product.slug}`}>{product.title}</Link>
      </h3>
      <p className="product-price">
        {formatPrice(product.min_price)}{" "}
        {compare && compare > product.min_price ? (
          <del>{formatPrice(compare)}</del>
        ) : null}
      </p>
    </Card>
  );
}
