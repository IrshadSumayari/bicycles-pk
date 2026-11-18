import Link from "next/link";
import { ArrowUpRight } from "lucide-react";
import {
  categoryHref,
  sectionById,
  type SectionId,
} from "../../shared/bicycles";
import { catalog, safeCatalog } from "@/lib/catalog";
import { sectionPhotos } from "@/lib/section-photos";
import { SectionIcon } from "./section-icon";
import { SplitTile } from "./split-tile";
import { ProductCard } from "./product-card";
import { ProductCarousel } from "./product-carousel";
// Section landing page in the style of the listing reference: header,
// category pills, two large tiles, then a carousel per category.
export async function SectionPage({ id }: { id: SectionId }) {
  const section = sectionById(id);
  const [general, ...categories] = section.categories;
  const [photos, rows] = await Promise.all([
    sectionPhotos(section),
    Promise.all(
      categories.map((c) =>
        safeCatalog(
          () => catalog.list({ category: c.name, limit: 8, sort: "new" }),
          [],
        ),
      ),
    ),
  ]);
  const shelves = categories
    .map((category, i) => ({ category, products: rows[i] }))
    .filter((shelf) => shelf.products.length > 0);
  const allHref = "/search?section=" + section.id;
  return (
    <div className="lv-section-page">
      <section className="lv-section-hero" aria-labelledby="section-title">
        <p className="lv-eyebrow">BICYCLES.PK · {section.label.toUpperCase()}</p>
        <h1 id="section-title">{section.label}</h1>
        <p>{section.description}</p>
        <nav
          className="lv-category-pills"
          aria-label={section.label + " categories"}
        >
          <Link href={allHref}>All {section.label.toLowerCase()}</Link>
          {categories.map((c) => (
            <Link key={c.slug} href={categoryHref(c.name)}>
              {c.name}
            </Link>
          ))}
          {general && (
            <Link href={categoryHref(general.name)}>Other</Link>
          )}
        </nav>
      </section>
      <div className="lv-split-tiles">
        {categories.slice(0, 2).map((c) => (
          <SplitTile
            key={c.slug}
            title={c.name}
            href={categoryHref(c.name)}
            image={photos[c.name]}
            icon={<SectionIcon id={id} size={96} strokeWidth={0.9} />}
          />
        ))}
      </div>
      {shelves.map(({ category, products }) => (
        <section
          key={category.slug}
          className="lv-shelf"
          aria-labelledby={"shelf-" + category.slug}
        >
          <div className="lv-shelf-top">
            <h2 id={"shelf-" + category.slug}>{category.name}</h2>
            <Link className="lv-link" href={categoryHref(category.name)}>
              Shop all <ArrowUpRight size={16} />
            </Link>
          </div>
          <ProductCarousel label={category.name}>
            {products.map((p) => (
              <ProductCard key={p.style_id} product={p} />
            ))}
          </ProductCarousel>
        </section>
      ))}
      {shelves.length === 0 && (
        <section
          className="lv-section-categories"
          aria-label={section.label + " categories"}
        >
          {categories.slice(2).map((category) => (
            <Link
              key={category.slug}
              href={categoryHref(category.name)}
              className="lv-section-category"
            >
              <div className="lv-section-category-art">
                <SectionIcon id={id} size={48} strokeWidth={1.25} />
                <ArrowUpRight className="lv-section-category-arrow" size={20} />
              </div>
              <h2>{category.name}</h2>
              <p>{category.description}</p>
            </Link>
          ))}
        </section>
      )}
      <div className="lv-section-more">
        <Link className="lv-pill-button lv-pill-dark" href={allHref}>
          Shop all {section.label.toLowerCase()}
        </Link>
      </div>
    </div>
  );
}
