import Link from "next/link";
import { ArrowUpRight, Ruler } from "lucide-react";
import { shopSections } from "../../shared/bicycles";
import { ProductCard } from "./product-card";
import { ProductCarousel } from "./product-carousel";
import { SectionIcon } from "./section-icon";
import { LandingHero } from "./landing-hero";
import type { CatalogRow } from "@/lib/types";
export function Home({
  featured,
  kids,
}: {
  featured: CatalogRow[];
  kids: CatalogRow[];
}) {
  return (
    <div className="lv-home lv-landing">
      <LandingHero />
      <section
        id="collections"
        className="lv-section"
        aria-labelledby="collection-title"
      >
        <div className="lv-section-top">
          <div>
            <p className="lv-eyebrow">SHOP BY SECTION</p>
            <h2 id="collection-title">Find your ride.</h2>
          </div>
          <Link className="lv-link" href="/collections">
            Explore all <ArrowUpRight size={17} />
          </Link>
        </div>
        <div className="lv-section-categories">
          {shopSections.map((s) => (
            <Link className="lv-section-category" href={s.href} key={s.id}>
              <div className="lv-section-category-art">
                <SectionIcon id={s.id} size={48} strokeWidth={1.25} />
                <ArrowUpRight className="lv-section-category-arrow" size={20} />
              </div>
              <h3>{s.label}</h3>
              <p>{s.description}</p>
            </Link>
          ))}
        </div>
      </section>
      {featured.length > 0 && (
        <section className="lv-section" aria-labelledby="arrivals-title">
          <div className="lv-section-top">
            <div>
              <p className="lv-eyebrow">NEW ARRIVALS</p>
              <h2 id="arrivals-title">Just landed.</h2>
            </div>
            <Link className="lv-link" href="/search?sort=new">
              Shop new arrivals <ArrowUpRight size={17} />
            </Link>
          </div>
          <ProductCarousel label="new arrivals">
            {featured.map((p) => (
              <ProductCard key={p.style_id} product={p} />
            ))}
          </ProductCarousel>
        </section>
      )}
      <section className="lv-feature-split" aria-labelledby="kids-title">
        <div className="lv-feature-art" aria-hidden="true">
          <SectionIcon id="kids" size={120} strokeWidth={0.9} />
        </div>
        <div className="lv-feature-copy">
          <p className="lv-eyebrow">KIDS BIKES</p>
          <h2 id="kids-title">First pedals. Big adventures.</h2>
          <p>
            Balance bikes, training-wheel bikes and junior bikes, sized by wheel
            and age so they fit from the first ride.
          </p>
          <div className="lv-feature-actions">
            <Link className="lv-pill-button lv-pill-dark" href="/kids">
              Shop kids bikes
            </Link>
            <Link className="lv-link" href="/fit-guide#kids-sizes">
              <Ruler size={16} /> Kids size chart
            </Link>
          </div>
        </div>
      </section>
      {kids.length > 0 && (
        <section className="lv-section" aria-label="Kids bikes">
          <ProductCarousel label="kids bikes">
            {kids.map((p) => (
              <ProductCard key={p.style_id} product={p} />
            ))}
          </ProductCarousel>
        </section>
      )}
      <section className="lv-service-band" aria-labelledby="service-title">
        <div>
          <p className="lv-eyebrow">RIDE WITH CONFIDENCE</p>
          <h2 id="service-title">Assembled, checked and ready to ride.</h2>
          <p>
            Every bike is built and safety-checked before it leaves us. Need
            help choosing a size, or want a test ride? Talk to us.
          </p>
        </div>
        <div className="lv-feature-actions">
          <Link className="lv-pill-button" href="/pages/contact">
            Book a test ride
          </Link>
          <Link className="lv-pill-button lv-pill-outline" href="/accessories">
            Shop accessories
          </Link>
        </div>
      </section>
    </div>
  );
}
