import Image from "next/image";
import Link from "next/link";
import { ArrowUpRight, Ruler, ShieldCheck, Sparkles } from "lucide-react";
import {
  bagCategories,
  bagCategoryHref,
  bagSizeGuide,
} from "../../../shared/bags";
import { BagArt } from "@/components/bag-art";
import { ProductCard } from "@/components/product-card";
import { bagCatalog } from "@/lib/bag-catalog";
export const revalidate = 60;
export const metadata = {
  title: "Bags & Handbags",
  description:
    "Shop women's tote bags, shoulder bags, crossbody bags, clutches, mini bags, backpacks and wallets at LadyVogue Pakistan.",
};
const scale: Record<string, number> = {
  Mini: 0.5,
  Small: 0.62,
  Medium: 0.76,
  Large: 0.9,
  "Extra large": 1,
};
export default async function BagsPage() {
  const { photos, newest } = await bagCatalog();
  const shapes = bagCategories.slice(1);
  const heroPhoto =
    photos["Shoulder Bags"] ?? photos["Tote Bags"] ?? Object.values(photos)[0];
  return (
    <div className="lv-bags-page">
      <section className="lv-bags-hero">
        <div>
          <p className="lv-eyebrow">LADYVOGUE BAGS</p>
          <h1>
            Carry it well.
            <br />
            <em>Everything, beautifully kept.</em>
          </h1>
          <p>
            Totes for full days, crossbodies for busy errands and clutches for
            the evenings worth dressing up for. Find the shape that fits your
            day.
          </p>
          <div className="lv-bags-actions">
            <a className="lv-button" href="#bag-shapes">
              Shop by shape <ArrowUpRight size={17} />
            </a>
            <a className="lv-button lv-button-outline" href="#size-guide">
              What fits? <Ruler size={17} />
            </a>
          </div>
        </div>
        {heroPhoto ? (
          <div className="lv-bags-hero-photo">
            <Image
              src={heroPhoto}
              alt=""
              fill
              priority
              sizes="(max-width:600px) 100vw, 45vw"
            />
          </div>
        ) : (
          <div className="lv-bags-hero-art" aria-hidden="true">
            <BagArt kind="shoulder-bags" />
            <BagArt kind="mini-bags" />
          </div>
        )}
      </section>

      <nav className="lv-bags-strip" aria-label="Bag shapes">
        {shapes.map((c) => (
          <Link key={c.slug} href={bagCategoryHref(c.name)}>
            <span>
              <BagArt kind={c.slug} />
            </span>
            {c.name.replace(" Bags", "")}
          </Link>
        ))}
      </nav>

      <section
        id="bag-shapes"
        className="lv-bags-shapes"
        aria-labelledby="bag-shapes-heading"
      >
        <p className="lv-eyebrow">SHOP BY SHAPE</p>
        <h2 id="bag-shapes-heading">Find your everyday favourite.</h2>
        <div className="lv-bags-grid">
          {shapes.map((c) => (
            <Link
              key={c.slug}
              href={bagCategoryHref(c.name)}
              className="lv-bags-category"
            >
              <div className="lv-bags-category-art">
                {photos[c.name] ? (
                  <Image
                    className="lv-bags-photo"
                    src={photos[c.name]}
                    alt=""
                    fill
                    sizes="(max-width:600px) 45vw, 23vw"
                  />
                ) : (
                  <BagArt kind={c.slug} />
                )}
                <ArrowUpRight size={20} />
              </div>
              <h3>{c.name}</h3>
              <p>{c.description}</p>
            </Link>
          ))}
        </div>
        <Link className="lv-link" href={bagCategoryHref("Bags")}>
          More bags <ArrowUpRight size={17} />
        </Link>
      </section>

      {newest.length > 0 && (
        <section className="lv-section lv-arrivals">
          <div className="lv-section-top">
            <div>
              <p className="lv-eyebrow">NEW IN BAGS</p>
              <h2>Just arrived.</h2>
            </div>
          </div>
          <div className="lv-product-grid">
            {newest.map((p) => (
              <ProductCard key={p.style_id} product={p} />
            ))}
          </div>
        </section>
      )}

      <section
        id="size-guide"
        className="lv-bags-sizes"
        aria-labelledby="bag-size-heading"
      >
        <p className="lv-eyebrow">BAG SIZE GUIDE</p>
        <h2 id="bag-size-heading">What fits inside?</h2>
        <p className="lv-bags-intro">
          A quick guide to our size names. Every product lists its own measured
          width, height, depth and strap drop, so check the product details
          before you choose.
        </p>
        <ol className="lv-bags-size-list">
          {bagSizeGuide.map((s) => (
            <li key={s.size}>
              <div
                className="lv-bags-size-art"
                style={{ "--bag-scale": scale[s.size] } as React.CSSProperties}
              >
                <BagArt kind="tote-bags" />
              </div>
              <h3>{s.size}</h3>
              <p className="lv-bags-size-dim">{s.dimensions}</p>
              <p>{s.fits}</p>
            </li>
          ))}
        </ol>
      </section>

      <aside id="care" className="lv-bags-care" aria-label="Choosing a bag">
        <div>
          <Ruler size={26} strokeWidth={1.2} />
          <h2>Measured, not guessed.</h2>
          <p>
            Width, height and depth are measured across the outside of the bag.
            Strap drop is the distance from the top of the strap to the top of
            the bag.
          </p>
        </div>
        <div>
          <Sparkles size={26} strokeWidth={1.2} />
          <h2>What’s in the box.</h2>
          <p>
            Detachable straps, pouches or dust bags are listed on each product
            when they are included. Colours can look slightly different on
            different screens.
          </p>
        </div>
        <div>
          <ShieldCheck size={26} strokeWidth={1.2} />
          <h2>A little care.</h2>
          <p>
            Store bags stuffed and upright, away from direct sunlight. Wipe with
            a soft dry cloth and follow the care notes on each product.
          </p>
        </div>
      </aside>
    </div>
  );
}
