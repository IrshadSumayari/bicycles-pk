import "server-only";
import { bagCategories } from "../../shared/bags";
import { catalog, safeCatalog } from "./catalog";
import { imageUrl } from "./helpers";
import type { CatalogRow } from "./types";

// Up to four newest published bags per category: the first photographed one
// becomes the category photo, and all of them feed the "New in" row.
export async function bagCatalog(): Promise<{
  photos: Record<string, string>;
  newest: CatalogRow[];
}> {
  const lists = await Promise.all(
    bagCategories.map((c) =>
      safeCatalog(() => catalog.list({ category: c.name, limit: 4 }), []),
    ),
  );
  const photos: Record<string, string> = {};
  bagCategories.forEach((c, i) => {
    const url = imageUrl(lists[i].find((row) => row.image_path)?.image_path);
    if (url) photos[c.name] = url;
  });
  // Interleave categories so the row shows a mix of shapes.
  const seen = new Set<string>();
  const newest: CatalogRow[] = [];
  for (let n = 0; n < 4; n++)
    for (const list of lists) {
      const row = list[n];
      if (row && !seen.has(row.style_id)) {
        seen.add(row.style_id);
        newest.push(row);
      }
    }
  return { photos, newest: newest.slice(0, 8) };
}
