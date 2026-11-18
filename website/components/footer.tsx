import Link from "next/link";
import { supportLinks, legalLinks } from "@/lib/shop-navigation";
import { brand } from "@/lib/brand";
import { BrandLogo } from "./brand-logo";
import { Appearance } from "./appearance";
import { shopSections } from "../../shared/bicycles";
import type { buildNavigation } from "@/lib/navigation";
export function Footer({
  navigation,
}: {
  navigation: ReturnType<typeof buildNavigation>;
}) {
  void navigation;
  return (
    <footer className="lv-footer">
      <div className="lv-footer-top">
        <div className="lv-footer-brand">
          <Link href="/" aria-label="Bicycles.pk home">
            <BrandLogo />
          </Link>
          <p>
            Bicycles, kids bikes, sports bikes,
            <br />
            accessories and parts.
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
          {shopSections.map((s) => (
            <Link key={s.id} href={s.href}>
              {s.label}
            </Link>
          ))}
          <Link href="/collections">All collections</Link>
        </div>
        <div>
          <h3>Riding with us</h3>
          <Link href="/fit-guide">Size guide</Link>
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
          © {new Date().getFullYear()} Bicycles.pk. All rights reserved.
        </span>
        <nav className="lv-legal-links" aria-label="Legal information">
          {legalLinks.map((link) => (
            <Link key={link.href} href={link.href}>
              {link.label}
            </Link>
          ))}
        </nav>
        <span>bicycles.pk</span>
      </div>
    </footer>
  );
}
