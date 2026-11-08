import { Home } from "@/components/home";
import { catalog, safeCatalog } from "@/lib/catalog";
import { shopCategories, categoryHref } from "@/lib/ladyvogue";
export const revalidate = 60;
export default async function HomePage() {
  const [collections, featured] = await Promise.all([
    safeCatalog(catalog.collections, []),
    safeCatalog(() => catalog.list({ limit: 4, sort: "new" }), []),
  ]);
  return (
    <Home
      categories={shopCategories.map((c) => ({
        ...c,
        href: categoryHref(c.slug, c.query, collections),
      }))}
      featured={featured}
    />
  );
}
