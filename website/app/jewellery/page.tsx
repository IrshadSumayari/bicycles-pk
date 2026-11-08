import Image from "next/image";
import Link from "next/link";
import { ArrowUpRight, Gem } from "lucide-react";
import {
  jewelleryCategories,
  jewelleryCategoryHref,
} from "../../../shared/jewellery";
import { JewelleryArt } from "@/components/jewellery-art";
import { jewelleryPhotos } from "@/lib/jewellery-photos";
export const revalidate = 60;
export const metadata = {
  title: "Jewellery",
  description:
    "Explore earrings, necklaces, rings, bracelets, bangles, anklets and jewellery sets at LadyVogue Pakistan.",
};
export default async function JewelleryPage() {
  const photos = await jewelleryPhotos();
  const heroPhoto = photos["Jewellery Sets"] ?? Object.values(photos)[0];
  return (
    <div className="lv-jewellery-page">
      <section className="lv-jewellery-hero">
        <div>
          <p className="lv-eyebrow">LADYVOGUE JEWELLERY</p>
          <h1>
            The little things.
            <br />
            <em>The lovely things.</em>
          </h1>
          <p>
            From your favourite everyday pair to a piece for a special moment.
            Find the finishing touch that feels like you.
          </p>
          <a className="lv-button" href="#jewellery-categories">
            Explore the edit <ArrowUpRight size={17} />
          </a>
        </div>
        {heroPhoto ? (
          <div className="lv-jewellery-hero-photo">
            <Image
              src={heroPhoto}
              alt=""
              fill
              priority
              sizes="(max-width:600px) 100vw, 45vw"
            />
          </div>
        ) : (
          <div className="lv-jewellery-hero-art">
            <JewelleryArt />
          </div>
        )}
      </section>
      <section
        id="jewellery-categories"
        className="lv-jewellery-categories"
        aria-labelledby="jewellery-heading"
      >
        <p className="lv-eyebrow">A LITTLE SOMETHING THAT SHINES</p>
        <h2 id="jewellery-heading">Find your finishing touch.</h2>
        <div className="lv-jewellery-grid">
          {jewelleryCategories.slice(1).map((category) => (
            <Link
              key={category.slug}
              href={jewelleryCategoryHref(category.name)}
              className="lv-jewellery-category"
            >
              <div className="lv-jewellery-category-art">
                {photos[category.name] ? (
                  <Image
                    className="lv-jewellery-photo"
                    src={photos[category.name]}
                    alt=""
                    fill
                    sizes="(max-width:600px) 45vw, 23vw"
                  />
                ) : (
                  <JewelleryArt kind={category.slug} />
                )}
                <ArrowUpRight size={20} />
              </div>
              <h3>{category.name}</h3>
              <p>{category.description}</p>
            </Link>
          ))}
        </div>
        <Link className="lv-link" href={jewelleryCategoryHref("Jewellery")}>
          More jewellery <ArrowUpRight size={17} />
        </Link>
      </section>
      <aside id="choosing" className="lv-jewellery-guide">
        <Gem size={30} strokeWidth={1} />
        <div>
          <h2>A little care in choosing.</h2>
          <p>
            Check each product’s material, finish, size and whether it is sold
            as a single item, pair or complete set. Ring sizes and lengths
            follow the labels shown on each product; check the product
            measurements and sizing system before choosing.
          </p>
          <p>
            Discover product photographs, materials and sizing on each listing.
          </p>
        </div>
      </aside>
    </div>
  );
}
