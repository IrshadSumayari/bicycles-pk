import type { MetadataRoute } from 'next';
import { isProductionSite, siteUrl } from '@/lib/helpers';
export default function robots(): MetadataRoute.Robots {
  // Only the live shop is crawled; staging and previews are closed to crawlers.
  if (!isProductionSite()) return { rules: { userAgent: '*', disallow: '/' } };
  return {
    rules: { userAgent: '*', allow: '/', disallow: '/search' },
    sitemap: siteUrl('/sitemap.xml'),
  };
}
