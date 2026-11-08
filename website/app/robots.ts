import type { MetadataRoute } from 'next';
import { siteUrl } from '@/lib/helpers';
export default function robots(): MetadataRoute.Robots {
  return {
    rules: { userAgent: '*', allow: '/', disallow: '/search' },
    sitemap: siteUrl('/sitemap.xml'),
  };
}
