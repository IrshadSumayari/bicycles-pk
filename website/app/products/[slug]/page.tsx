import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { headers } from "next/headers";
import { sectionOfCategory } from "../../../../shared/bicycles";
import { catalog, safeCatalog } from "@/lib/catalog";
import { imageUrl, jsonScript, productJsonLd, siteUrl } from "@/lib/helpers";
import { ProductDetail } from "@/components/product-detail";
import { RelatedProducts } from "@/components/related-products";
type Props = { params: Promise<{ slug: string }> };
// Add-on categories suggested under a bike ("Complete your ride").
const addOnCategories = ["Helmets", "Locks", "Lights"];
const bikeSections = new Set(["bicycles", "kids", "sports", "ebikes"]);
export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { slug } = await params;
  try {
    const product = await catalog.product(slug);
    if (!product)
      return { title: "Product not found", robots: { index: false } };
    const image = imageUrl(product.images[0]?.storage_path);
    return {
      title: product.title,
      description: product.description?.slice(0, 160) || undefined,
      alternates: { canonical: `/products/${slug}` },
      openGraph: {
        title: product.title,
        description: product.description?.slice(0, 160) || undefined,
        images: image
          ? [{ url: image, alt: product.images[0]?.alt || product.title }]
          : [],
      },
    };
  } catch {
    return { title: "Bicycles" };
  }
}
export default async function ProductPage({ params }: Props) {
  const { slug } = await params;
  let product;
  try {
    product = await catalog.product(slug);
  } catch {
    return (
      <section className="product-route">
        <h1 className="text-3xl">Please visit again shortly</h1>
        <p className="muted my-5">
          We couldn’t load this product. Please try again in a moment.
        </p>
        <Link className="button" href="/search">
          Browse bicycles
        </Link>
      </section>
    );
  }
  if (!product) notFound();
  const url = siteUrl(`/products/${product.slug}`);
  const isBike = bikeSections.has(
    sectionOfCategory(product.category ?? undefined)?.id ?? "",
  );
  // Bikes show up to three sibling models in the switcher; the rest of the
  // related products stay under "You may also like".
  const models = isBike ? product.related.slice(0, 3) : [];
  const related = product.related.slice(models.length);
  const addOns = isBike
    ? (
        await Promise.all(
          addOnCategories.map((category) =>
            safeCatalog(
              () => catalog.list({ category, limit: 1, sort: "new" }),
              [],
            ),
          ),
        )
      ).flat()
    : [];
  return (
    <>
      <ProductDetail
        key={product.slug}
        initial={product}
        pageUrl={url}
        models={models}
        addOns={addOns}
      />
      <script
        nonce={(await headers()).get("x-nonce") || undefined}
        type="application/ld+json"
        dangerouslySetInnerHTML={{
          __html: jsonScript(productJsonLd(product, url)),
        }}
      />
      {!!related.length && (
        <section className="related-products section-space">
          <div className="section-heading">
            <h2>You may also like</h2>
          </div>
          <RelatedProducts products={related} />
        </section>
      )}
    </>
  );
}
