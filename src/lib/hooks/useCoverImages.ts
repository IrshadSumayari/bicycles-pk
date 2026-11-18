import { useQuery } from '@tanstack/react-query';
import { webCatalogService } from '../services';
import { queryKeys } from '../queryClient';
import type { Product } from '../../types';

// Photos uploaded in the style editor live in product_images, not the legacy
// style image_url. Returns a lookup that prefers image_url, then a photo of the
// variant's colour, then the style's first photo.
export function useCoverImages(products: Pick<Product, 'styleId'>[]) {
  const styleIds = [...new Set(products.map(product => product.styleId).filter(Boolean))].sort();
  const covers = useQuery({
    queryKey: queryKeys.webCovers(styleIds),
    queryFn: () => webCatalogService.coverImages(styleIds),
    enabled: styleIds.length > 0,
    staleTime: 5 * 60 * 1000,
  });
  return (product: Pick<Product, 'styleId' | 'image' | 'color'>) =>
    product.image ||
    covers.data?.get(product.styleId + '|' + (product.color ?? '').toLowerCase()) ||
    covers.data?.get(product.styleId);
}
