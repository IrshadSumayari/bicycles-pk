import type { Collection } from "./types";
export function buildNavigation(
  collections: Pick<Collection, "slug" | "name">[],
) {
  const seen = new Set<string>();
  return collections
    .filter(({ slug, name }) => {
      if (
        !name.trim() ||
        !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(slug) ||
        slug.length > 120 ||
        seen.has(slug)
      )
        return false;
      seen.add(slug);
      return true;
    })
    .map(({ slug, name }) => ({ label: name, href: `/collections/${slug}` }));
}
