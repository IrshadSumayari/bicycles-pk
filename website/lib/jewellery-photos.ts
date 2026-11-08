import "server-only";
import { jewelleryCategories } from "../../shared/jewellery";
import { catalog, safeCatalog } from "./catalog";
import { imageUrl } from "./helpers";
// The newest published product photo in each jewellery category. Categories
// without a photographed product are left out and keep their illustration.
export async function jewelleryPhotos(): Promise<Record<string, string>> {
  const entries = await Promise.all(
    jewelleryCategories.map(async (c) => {
      const rows = await safeCatalog(
        () => catalog.list({ category: c.name, limit: 1 }),
        [],
      );
      return [c.name, imageUrl(rows[0]?.image_path)];
    }),
  );
  return Object.fromEntries(entries.filter(([, url]) => url));
}
