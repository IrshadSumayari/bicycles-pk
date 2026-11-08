import Image from "next/image";
import Link from "next/link";
import { ArrowUpRight } from "lucide-react";
import { shopSections } from "../../../shared/bicycles";
import { catalog, safeCatalog } from "@/lib/catalog";
import { imageUrl } from "@/lib/helpers";
import { ShopHeading } from "@/components/shop-heading";
import { SectionIcon } from "@/components/section-icon";
export const revalidate = 60;
export const metadata = { title: "Shop all" };
export default async function Page() {
  const collections = await safeCatalog(catalog.collections, []);
  return (
    <>
      <ShopHeading
        title="Everything for the ride."
        description="Bicycles for every age and road, plus the accessories and parts that keep you riding."
      />
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
