import {
  jewelleryCategories,
  jewelleryCategoryHref,
} from "../../shared/jewellery";
import { bagCategories, bagCategoryHref } from "../../shared/bags";
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
export function catalogueLink(
  slug: string,
  category: string,
  collections: { slug: string }[],
) {
  return collections.some((c) => c.slug === slug)
    ? `/collections/${slug}`
    : `/search?${new URLSearchParams({ category })}`;
}
export function buildShopMenus(collections: { slug: string }[]): ShopMenu[] {
  const category = (
    label: string,
    slug = label.toLowerCase(),
    stored = label,
  ) => ({ label, href: catalogueLink(slug, stored, collections) });
  const available = (items: [string, string][]) =>
    items
      .filter(([, slug]) => collections.some((c) => c.slug === slug))
      .map(([label, slug]) => ({ label, href: `/collections/${slug}` }));
  return [
    {
      ...category("Bras"),
      children: [
        ...available([
          ["Cotton bras", "cotton-bras"],
          ["Seamless bras", "seamless-bras"],
          ["Padded bras", "padded-bras"],
          ["Non-padded bras", "non-padded-bras"],
          ["Wireless bras", "wireless-bras"],
          ["Wired bras", "wired-bras"],
          ["Sports bras", "sports-bras"],
          ["Nursing bras", "nursing-bras"],
          ["Plus-size bras", "plus-size-bras"],
        ]),
        { label: "Find your fit", href: "/fit-guide" },
      ],
    },
    {
      ...category("Panties"),
      children: available([
        ["Cotton panties", "cotton-panties"],
        ["Seamless panties", "seamless-panties"],
        ["Briefs", "briefs"],
        ["Multipacks", "panty-multipacks"],
      ]),
    },
    {
      ...category("Nightwear"),
      children: [
        category("Robes"),
        ...available([
          ["Pyjama sets", "pyjama-sets"],
          ["Nighties", "nighties"],
        ]),
      ],
    },
    {
      label: "Jewellery",
      href: "/jewellery",
      children: jewelleryCategories
        .filter((c) => c.name !== "Jewellery")
        .map((c) => ({ label: c.name, href: jewelleryCategoryHref(c.name) })),
    },
    {
      label: "Bags",
      href: "/bags",
      children: bagCategories
        .filter((c) => c.name !== "Bags")
        .map((c) => ({ label: c.name, href: bagCategoryHref(c.name) })),
    },
    {
      label: "More to explore",
      href: "/collections",
      children: [
        category("Matching sets", "matching-sets", "Lingerie Sets"),
        category("Shapewear"),
        category("Camisoles"),
        { label: "New arrivals", href: "/search?sort=new" },
        { label: "All collections", href: "/collections" },
      ],
    },
    { label: "Help", href: "/pages/contact", children: supportLinks },
  ];
}
