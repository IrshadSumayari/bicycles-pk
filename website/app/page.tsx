import { Home } from "@/components/home";
import { catalog, safeCatalog } from "@/lib/catalog";
export const revalidate = 60;
export default async function HomePage() {
  const featured = await safeCatalog(
    () => catalog.list({ limit: 4, sort: "new" }),
    [],
  );
  return <Home featured={featured} />;
}
