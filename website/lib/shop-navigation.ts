import { categoryHref, shopSections } from "../../shared/bicycles";
export type ShopLink = { label: string; href: string };
export type ShopMenu = ShopLink & { children: ShopLink[] };
export const supportLinks: ShopLink[] = [
  { label: "Contact us", href: "/pages/contact" },
  { label: "FAQs", href: "/pages/faq" },
  { label: "Track my order", href: "/account/track" },
  { label: "Delivery information", href: "/policies/shipping-policy" },
  { label: "Returns & exchanges", href: "/policies/refund-policy" },
  { label: "Payment methods", href: "/policies/payment-methods" },
];
export const legalLinks: ShopLink[] = [
  { label: "Privacy policy", href: "/policies/privacy-policy" },
  { label: "Terms & conditions", href: "/policies/terms-of-service" },
];
// Collections are kept for the existing shop API; section menus link to the
// exact stored category names.
export function buildShopMenus(collections: { slug: string }[] = []): ShopMenu[] {
  void collections;
  return [
    ...shopSections.map((section) => ({
      label: section.label,
      href: section.href,
      children: section.categories
        .slice(1)
        .map((c) => ({ label: c.name, href: categoryHref(c.name) })),
    })),
    { label: "Help", href: "/pages/contact", children: supportLinks },
  ];
}
