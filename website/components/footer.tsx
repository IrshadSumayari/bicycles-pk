import Link from "next/link";
import { supportLinks, legalLinks } from "@/lib/shop-navigation";
import { brand } from "@/lib/brand";
import { BrandLogo } from "./brand-logo";
import { Appearance } from "./appearance";
import { shopCategories, categoryHref } from "@/lib/ladyvogue";
import type { buildNavigation } from "@/lib/navigation";
export function Footer({
  navigation,
}: {
  navigation: ReturnType<typeof buildNavigation>;
}) {
  const collections = navigation.map((n) => ({
    slug: n.href.split("/").pop() || "",
  }));
  return (
    <footer className="lv-footer">
      <div className="lv-footer-top">
        <div className="lv-footer-brand">
          <Link href="/" aria-label="LadyVogue home">
            <BrandLogo />
          </Link>
          <p>
            Your everyday, beautifully considered.
            <br />
            Lingerie, nightwear, jewellery, bags and little luxuries.
          </p>
          <span>PAKISTAN · PRICES IN PKR</span>
          {brand.phone && (
            <p>
              <a href={"tel:" + brand.phone}>Call {brand.phone}</a>
            </p>
          )}
          {brand.email && (
            <p>
              <a href={"mailto:" + brand.email}>{brand.email}</a>
            </p>
          )}
          <Appearance />
        </div>
        <div>
          <h3>Explore</h3>
          {shopCategories.map((c) => (
            <Link
              key={c.slug}
              href={categoryHref(c.slug, c.query, collections)}
            >
              {c.label}
            </Link>
          ))}
          <Link href="/jewellery">Jewellery</Link>
          <Link href="/bags">Bags</Link>
          <Link href="/collections">All collections</Link>
        </div>
        <div>
          <h3>Made for you</h3>
          <Link href="/fit-guide">Find your fit</Link>
          <Link href="/about">Our story</Link>
          <Link href="/account">My account</Link>
          <Link href="/account/orders">My orders</Link>
        </div>
        <div>
          <h3>Customer care</h3>
          {supportLinks.map((link) => (
            <Link key={link.href} href={link.href}>
              {link.label}
            </Link>
          ))}
        </div>
      </div>
      <div className="lv-footer-bottom">
        <span>
          © {new Date().getFullYear()} LadyVogue. All rights reserved.
        </span>
        <nav className="lv-legal-links" aria-label="Legal information">
          {legalLinks.map((link) => (
            <Link key={link.href} href={link.href}>
              {link.label}
            </Link>
          ))}
        </nav>
        <span>ladyvogue.pk</span>
      </div>
    </footer>
  );
}
