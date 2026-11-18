import { shopSections } from "../../shared/bicycles";
import type { MetadataRoute } from 'next';
import { catalog } from '@/lib/catalog';
import { siteUrl } from '@/lib/helpers';
export const revalidate = 60;
export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const urls: MetadataRoute.Sitemap = [{ url: siteUrl('/') }, ...shopSections.map((s) => ({ url: siteUrl(s.href) }))];
  try {
    const collections = await catalog.collections();
    urls.push(
      ...collections.map((collection) => ({
        url: siteUrl(`/collections/${collection.slug}`),
      })),
    );
    for (let offset = 0; ; offset += 48) {
      const products = await catalog.list({ limit: 48, offset, sort: 'new' });
      urls.push(
        ...products.map((product) => ({
          url: siteUrl(`/products/${product.slug}`),
        })),
      );
      if (
        !products.length ||
        offset + products.length >= Number(products[0].total_count)
      )
        break;
    }
  } catch {
    console.warn('Sitemap will refresh when the catalog is available.');
  }
  return urls;
}
