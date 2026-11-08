import Image from "next/image";
import Link from "next/link";
import { ArrowUpRight } from "lucide-react";
import {
  categoryHref,
  sectionById,
  type SectionId,
} from "../../shared/bicycles";
import { sectionPhotos } from "@/lib/section-photos";
import { SectionIcon } from "./section-icon";
// Landing page for one shop section: its categories, each linking to the
// filtered catalogue. Redesigned in the listing milestone.
export async function SectionPage({ id }: { id: SectionId }) {
  const section = sectionById(id);
  const photos = await sectionPhotos(section);
  const [general, ...categories] = section.categories;
  return (
    <div className="lv-section-page">
      <section className="lv-section-hero" aria-labelledby="section-title">
        <p className="lv-eyebrow">BICYCLES.PK · {section.label.toUpperCase()}</p>
        <h1 id="section-title">{section.label}</h1>
        <p>{section.description}</p>
        <Link className="lv-button" href={categoryHref(general.name)}>
          Shop all {section.label.toLowerCase()} <ArrowUpRight size={17} />
        </Link>
      </section>
      <section className="lv-section-categories" aria-label={section.label + " categories"}>
        {categories.map((category) => (
          <Link
            key={category.slug}
            href={categoryHref(category.name)}
            className="lv-section-category"
          >
            <div className="lv-section-category-art">
              {photos[category.name] ? (
                <Image
                  src={photos[category.name]}
                  alt=""
                  fill
                  sizes="(max-width:600px) 45vw, 23vw"
                />
              ) : (
                <SectionIcon id={id} size={48} strokeWidth={1.25} />
              )}
              <ArrowUpRight className="lv-section-category-arrow" size={20} />
            </div>
            <h2>{category.name}</h2>
            <p>{category.description}</p>
          </Link>
        ))}
      </section>
    </div>
  );
}
