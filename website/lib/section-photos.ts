import "server-only";
import type { ShopSection } from "../../shared/bicycles";
import { catalog, safeCatalog } from "./catalog";
import { imageUrl } from "./helpers";
// The newest published product photo in each category of a section.
// Categories without a photographed product show their icon instead.
export async function sectionPhotos(
  section: ShopSection,
): Promise<Record<string, string>> {
  const entries = await Promise.all(
    section.categories.map(async (c) => {
      const rows = await safeCatalog(
        () => catalog.list({ category: c.name, limit: 1 }),
        [],
      );
      return [c.name, imageUrl(rows[0]?.image_path)];
    }),
  );
  return Object.fromEntries(entries.filter(([, url]) => url));
}
