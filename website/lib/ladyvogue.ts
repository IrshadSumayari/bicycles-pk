import { catalogueLink } from "./shop-navigation";
export const shopCategories = [
  {
    label: "Bras",
    slug: "bras",
    query: "bra",
    subtitle: "A little lift. A lot of confidence.",
    image: "/ladyvogue/campaign.webp",
    position: "22% 80%",
  },
  {
    label: "Panties",
    slug: "panties",
    query: "panty",
    subtitle: "Your everyday, beautifully covered.",
    image: "/ladyvogue/essentials.webp",
    position: "center",
  },
  {
    label: "Nightwear",
    slug: "nightwear",
    query: "night",
    subtitle: "For slow mornings and softer nights.",
    image: "/ladyvogue/nightwear.webp",
    position: "center",
  },
];
export function categoryHref(
  slug: string,
  query: string,
  collections: { slug: string }[],
) {
  const categories: Record<string, string> = {
    bras: "Bras",
    panties: "Panties",
    nightwear: "Nightwear",
    "matching-sets": "Lingerie Sets",
  };
  if (categories[slug])
    return catalogueLink(slug, categories[slug], collections);
  return collections.some((c) => c.slug === slug)
    ? "/collections/" + slug
    : "/search?q=" + encodeURIComponent(query);
}
