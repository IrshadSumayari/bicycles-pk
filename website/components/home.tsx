import Link from "next/link";
import { ArrowRight, ArrowUpRight, ShieldCheck, Truck, Wrench } from "lucide-react";
import { shopSections } from "../../shared/bicycles";
import { ProductCard } from "./product-card";
import { SectionIcon } from "./section-icon";
import type { CatalogRow } from "@/lib/types";
// Placeholder homepage. The full-bleed hero redesign is the landing-page milestone.
export function Home({ featured }: { featured: CatalogRow[] }) {
  return (
    <div className="lv-home">
      <section className="lv-hero" aria-labelledby="hero-title">
        <div className="lv-hero-copy">
          <p className="lv-eyebrow">
            <span /> BICYCLES.PK
          </p>
          <h1 id="hero-title">
            Ride further.
            <br />
            <em>Ride better.</em>
          </h1>
          <p className="lv-lead">
            City bikes, kids bikes, sports bikes and everything for the ride,
            delivered across Pakistan.
          </p>
          <Link className="lv-button" href="/bicycles">
            Shop bicycles <ArrowRight size={17} />
          </Link>
          <Link className="lv-quiet-link" href="/fit-guide">
            Find your frame size <ArrowUpRight size={15} />
          </Link>
        </div>
      </section>
      <ul className="lv-usp-strip" aria-label="Why shop with us">
        <li><ShieldCheck size={20} /> Warranty on every bike</li>
        <li><Wrench size={20} /> Assembled and checked</li>
        <li><Truck size={20} /> Delivery across Pakistan</li>
      </ul>
      <section id="collections" className="lv-section" aria-labelledby="collection-title">
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
        <section className="lv-section lv-arrivals">
          <div className="lv-section-top">
            <div>
              <p className="lv-eyebrow">NEW ARRIVALS</p>
              <h2>Just landed.</h2>
            </div>
            <Link className="lv-link" href="/search?sort=new">
              Shop new arrivals <ArrowUpRight size={17} />
            </Link>
          </div>
          <div className="lv-product-grid">
            {featured.slice(0, 4).map((p) => (
              <ProductCard key={p.style_id} product={p} />
            ))}
          </div>
        </section>
      )}
    </div>
  );
}
