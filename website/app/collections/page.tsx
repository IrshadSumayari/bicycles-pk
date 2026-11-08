import { JewelleryFeature } from "@/components/jewellery-feature";
import { BagsFeature } from "@/components/bags-feature";
import Image from "next/image";
import Link from "next/link";
import { ArrowUpRight } from "lucide-react";
import { catalog, safeCatalog } from "@/lib/catalog";
import { imageUrl } from "@/lib/helpers";
import { shopCategories, categoryHref } from "@/lib/ladyvogue";
import { ShopHeading } from "@/components/shop-heading";
export const revalidate = 60;
export const metadata = { title: "Shop the collections" };
export default async function Page() {
  const collections = await safeCatalog(catalog.collections, []);
  const additional = collections.filter(
    (c) => !shopCategories.some((s) => s.slug === c.slug),
  );
  return (
    <>
      <ShopHeading
        title="Your everyday, elevated."
        description="From your first layer to your last moment of the day. Find a little something that feels like you."
      />
      <section className="lv-shop-collections" aria-label="Shop by category">
        <div className="lv-category-grid">
          {shopCategories.map((c) => (
            <Link
              key={c.slug}
              className="lv-category"
              href={categoryHref(c.slug, c.query, collections)}
            >
              <div className="lv-category-photo">
                <Image
                  src={c.image}
                  alt={c.label + " collection inspiration"}
                  fill
                  sizes="(max-width:600px) 90vw, 30vw"
                  style={{ objectPosition: c.position }}
                />
                <span className="lv-round-arrow">
                  <ArrowUpRight size={20} />
                </span>
              </div>
              <div className="lv-category-title">
                <h2>{c.label}</h2>
                <span>Discover</span>
              </div>
              <p>{c.subtitle}</p>
            </Link>
          ))}
        </div>
        {additional.length > 0 && (
          <div className="lv-additional-collections">
            {additional.map((c) => (
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
      </section>
      <JewelleryFeature />
      <BagsFeature />
      <aside className="lv-shopping-note">
        <p>Not sure where to start?</p>
        <Link className="lv-link" href="/fit-guide">
          Find a fit that feels like you <ArrowUpRight size={16} />
        </Link>
      </aside>
    </>
  );
}
