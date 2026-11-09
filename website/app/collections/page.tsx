import Image from "next/image";
import Link from "next/link";
import { ArrowUpRight } from "lucide-react";
import { sectionById, shopSections } from "../../../shared/bicycles";
import { catalog, safeCatalog } from "@/lib/catalog";
import { imageUrl } from "@/lib/helpers";
import { ShopHeading } from "@/components/shop-heading";
import { SectionIcon } from "@/components/section-icon";
import { SplitTile } from "@/components/split-tile";
import { ProductCard } from "@/components/product-card";
import { ProductCarousel } from "@/components/product-carousel";
export const revalidate = 60;
export const metadata = { title: "Shop all" };
export default async function Page() {
  const bikes = sectionById("bicycles"),
    gear = sectionById("accessories");
  const [collections, rows] = await Promise.all([
    safeCatalog(catalog.collections, []),
    Promise.all(
      shopSections.map((s) =>
        safeCatalog(
          () =>
            catalog.list({
              categories: s.categories.map((c) => c.name),
              limit: 8,
              sort: "new",
            }),
          [],
        ),
      ),
    ),
  ]);
  const [bikePhoto, gearPhoto] = [0, shopSections.indexOf(gear)].map((i) =>
    imageUrl(rows[i]?.[0]?.image_path),
  );
  const shelves = shopSections
    .map((section, i) => ({ section, products: rows[i] }))
    .filter((shelf) => shelf.products.length > 0);
  return (
    <>
      <ShopHeading
        title="Everything for the ride."
        description="Bicycles for every age and road, plus the accessories and parts that keep you riding."
      />
      <div className="lv-split-tiles">
        <SplitTile
          title={"Shop " + bikes.label}
          href={bikes.href}
          image={bikePhoto}
          icon={<SectionIcon id="bicycles" size={96} strokeWidth={0.9} />}
        />
        <SplitTile
          title={"Shop " + gear.label}
          href={gear.href}
          image={gearPhoto}
          icon={<SectionIcon id="accessories" size={96} strokeWidth={0.9} />}
        />
      </div>
      {shelves.map(({ section, products }) => (
        <section
          key={section.id}
          className="lv-shelf"
          aria-labelledby={"shelf-" + section.id}
        >
          <div className="lv-shelf-top">
            <h2 id={"shelf-" + section.id}>{section.label}</h2>
            <Link className="lv-link" href={section.href}>
              Shop all <ArrowUpRight size={16} />
            </Link>
          </div>
          <ProductCarousel label={section.label}>
            {products.map((p) => (
              <ProductCard key={p.style_id} product={p} />
            ))}
          </ProductCarousel>
        </section>
      ))}
      <section className="lv-section-categories" aria-label="Shop by section">
        {shopSections.map((s) => (
          <Link key={s.id} className="lv-section-category" href={s.href}>
            <div className="lv-section-category-art">
              <SectionIcon id={s.id} size={48} strokeWidth={1.25} />
              <ArrowUpRight className="lv-section-category-arrow" size={20} />
            </div>
            <h2>{s.label}</h2>
            <p>{s.description}</p>
          </Link>
        ))}
      </section>
      {collections.length > 0 && (
        <div className="lv-additional-collections">
          {collections.map((c) => (
            <Link href={"/collections/" + c.slug} key={c.slug}>
              {imageUrl(c.hero_image_path) && (
                <Image
                  src={imageUrl(c.hero_image_path)!}
                  alt=""
                  width={500}
                  height={500}
                />
              )}
              <h2>{c.name}</h2>
              <ArrowUpRight size={18} />
            </Link>
          ))}
        </div>
      )}
    </>
  );
}
