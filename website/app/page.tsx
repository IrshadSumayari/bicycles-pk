import { Home } from "@/components/home";
import { catalog, safeCatalog } from "@/lib/catalog";
export const revalidate = 60;
export default async function HomePage() {
  const [featured, kids] = await Promise.all([
    safeCatalog(() => catalog.list({ limit: 8, sort: "new" }), []),
    safeCatalog(
      () => catalog.list({ category: "Kids Bicycles", limit: 8, sort: "new" }),
      [],
    ),
  ]);
  return <Home featured={featured} kids={kids} />;
}
