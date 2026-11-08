import { JewelleryFeature } from "@/components/jewellery-feature";
import { BagsFeature } from "@/components/bags-feature";
import Link from "next/link";
import Image from "next/image";
import {
  ArrowRight,
  ArrowUpRight,
  Flower2,
  Ruler,
  Heart,
  Sparkles,
} from "lucide-react";
import { ProductCard } from "./product-card";
import type { CatalogRow } from "@/lib/types";
type Category = {
  label: string;
  subtitle: string;
  image: string;
  position: string;
  href: string;
};
export function Home({
  categories,
  featured,
}: {
  categories: Category[];
  featured: CatalogRow[];
}) {
  return (
    <div className="lv-home">
      <section className="lv-hero" aria-labelledby="hero-title">
        <div className="lv-hero-copy">
          <p className="lv-eyebrow">
            <span /> THE LADYVOGUE EDIT
          </p>
          <h1 id="hero-title">
            Beautifully you.
            <br />
            <em>Every day.</em>
          </h1>
          <p className="lv-lead">
            Little luxuries. Everyday confidence.
            <br />
            Discover lingerie and nightwear for all the ways you are you.
          </p>
          <Link className="lv-button" href="#collections">
            Explore the collection <ArrowRight size={17} />
          </Link>
          <Link className="lv-quiet-link" href="/fit-guide">
            Find your perfect fit <ArrowUpRight size={15} />
          </Link>
          <div className="lv-hero-note">
            <span className="lv-monogram">LV</span>
            <span>
              YOUR EVERYDAY, ELEVATED.
              <br />
              <small>Lingerie · Nightwear · Essentials</small>
            </span>
          </div>
        </div>
        <div className="lv-hero-photo">
          <Image
            src="/ladyvogue/campaign.webp"
            alt="Blush lace lingerie and rose satin nightwear arranged on soft ivory linen"
            fill
            sizes="(max-width: 760px) 100vw, 57vw"
            preload
          />
          <span className="lv-photo-label">THE ART OF FEELING GOOD</span>
          <div className="lv-photo-caption">
            <span>
              The soft life
              <br />
              <em>starts here.</em>
            </span>
            <Link href={categories[2].href} aria-label="Discover nightwear">
              <ArrowUpRight />
            </Link>
          </div>
        </div>
      </section>
      <div className="lv-ribbon">
        <span>
          <Flower2 size={17} /> Everyday essentials
        </span>
        <span>
          <Heart size={17} /> A little something for you
        </span>
        <span>
          <Ruler size={17} /> A more confident fit
        </span>
      </div>
      <section
        className="lv-section"
        id="collections"
        aria-labelledby="collection-title"
      >
        <div className="lv-section-top">
          <div>
            <p className="lv-eyebrow">YOUR WORLD. YOUR WARDROBE.</p>
            <h2 id="collection-title">Find your everyday favourites.</h2>
          </div>
          <Link className="lv-link" href="/collections">
            Explore all <ArrowUpRight size={17} />
          </Link>
        </div>
        <div className="lv-category-grid">
          {categories.map((c, i) => (
            <Link className="lv-category" href={c.href} key={c.label}>
              <div className="lv-category-photo">
                <Image
                  src={c.image}
                  alt={c.label + " collection inspiration"}
                  fill
                  sizes="(max-width: 600px) 82vw, 31vw"
                  style={{ objectPosition: c.position }}
                />
                <span className="lv-category-number">0{i + 1} / THE EDIT</span>
                <span className="lv-round-arrow">
                  <ArrowUpRight size={20} />
                </span>
              </div>
              <div className="lv-category-title">
                <h3>{c.label}</h3>
                <span>Discover</span>
              </div>
              <p>{c.subtitle}</p>
            </Link>
          ))}
        </div>
      </section>
      {featured.length > 0 && (
        <section className="lv-section lv-arrivals">
          <div className="lv-section-top">
            <div>
              <p className="lv-eyebrow">FRESH FINDS</p>
              <h2>Meet your next favourites.</h2>
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
      <section className="lv-editorial" aria-labelledby="night-title">
        <div className="lv-editorial-photo">
          <Image
            src="/ladyvogue/nightwear.webp"
            alt="Ivory satin pajama set in soft afternoon light"
            fill
            sizes="(max-width: 760px) 100vw, 50vw"
          />
        </div>
        <div className="lv-editorial-copy">
          <Sparkles size={25} strokeWidth={1} />
          <p className="lv-eyebrow">THE WIND-DOWN EDIT</p>
          <h2 id="night-title">
            Stay in.
            <br />
            <em>Feel extraordinary.</em>
          </h2>
          <p>
            Switch off the day. Slip into your kind of comfort. Make a little
            room for softer evenings and unhurried mornings.
          </p>
          <Link href={categories[2].href} className="lv-button">
            Discover nightwear <ArrowRight size={17} />
          </Link>
          <span className="lv-editorial-footnote">A MOMENT JUST FOR YOU.</span>
        </div>
      </section>
      <JewelleryFeature />
      <BagsFeature />
      <section className="lv-fit" aria-labelledby="fit-title">
        <div className="lv-fit-icon">
          <Ruler size={37} strokeWidth={1} />
        </div>
        <div>
          <p className="lv-eyebrow">GOOD FIT. GOOD FEELING.</p>
          <h2 id="fit-title">Confidence starts with comfort.</h2>
          <p>
            A little guidance makes all the difference. Get to know your
            measurements and find the fit that feels like you.
          </p>
        </div>
        <Link className="lv-button lv-button-outline" href="/fit-guide">
          Explore the fit guide <ArrowUpRight size={17} />
        </Link>
      </section>
      <section className="lv-manifesto">
        <Flower2 size={29} strokeWidth={1} />
        <p className="lv-eyebrow">A NOTE FROM LADYVOGUE</p>
        <h2>
          For the woman you are.
          <br />
          <em>And every version of her.</em>
        </h2>
        <p>
          From the first layer to the last moment of the day, we believe
          everyday essentials deserve a little more thought, a little more
          beauty, and a lot more you.
        </p>
        <Link className="lv-link" href="/about">
          Our story <ArrowUpRight size={16} />
        </Link>
      </section>
    </div>
  );
}
