import { ProductCard } from "./product-card";
import type { Related } from "@/lib/types";
export function RelatedProducts({ products }: { products: Related[] }) {
  return (
    <div className="product-grid">
      {products.map((p) => (
        <ProductCard key={p.style_id} product={p} />
      ))}
    </div>
  );
}
