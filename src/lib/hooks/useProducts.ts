import { useEffect, useState } from 'react';
import {
  keepPreviousData,
  useInfiniteQuery,
  useQuery,
} from '@tanstack/react-query';
import { useApp } from '../../context/SupabaseAppContext';
import { productsService, type ProductSearchParams } from '../services';
import { queryKeys } from '../queryClient';

function useProductParams(params: ProductSearchParams) {
  const { state } = useApp();
  const text = params.q?.trim() ?? '';
  const [q, setQ] = useState(text);
  useEffect(() => {
    const timer = setTimeout(() => setQ(text), 300);
    return () => clearTimeout(timer);
  }, [text]);
  const canSeeCosts = ['admin', 'manager'].includes(
    state.currentUser?.role ?? '',
  );
  return {
    userId: state.currentUser?.id ?? '',
    params: { ...params, q, withCosts: !!params.withCosts && canSeeCosts },
    debouncing: q !== text,
  };
}

export function useProductSearch(input: ProductSearchParams, enabled = true) {
  const { userId, params, debouncing } = useProductParams(input);
  const query = useQuery({
    queryKey: queryKeys.productSearch(userId, params),
    queryFn: () => productsService.search(params),
    enabled: enabled && !!userId && !debouncing,
    placeholderData: keepPreviousData,
    staleTime: 30_000,
  });
  return { ...query, searching: debouncing || query.isFetching };
}

export function useInfiniteProducts(input: ProductSearchParams) {
  const { userId, params, debouncing } = useProductParams(input);
  const query = useInfiniteQuery({
    queryKey: queryKeys.infiniteProducts(userId, params),
    initialPageParam: 0,
    queryFn: ({ pageParam }) =>
      productsService.search({ ...params, limit: 60, offset: pageParam }),
    getNextPageParam: (last, pages) => {
      const loaded = pages.reduce((sum, page) => sum + page.rows.length, 0);
      return last.rows.length && loaded < last.total ? loaded : undefined;
    },
    enabled: !!userId && !debouncing,
    placeholderData: keepPreviousData,
    staleTime: 30_000,
  });
  return { ...query, searching: debouncing || query.isFetching };
}

export function useProductCategories(enabled = true) {
  return useQuery({
    queryKey: queryKeys.productCategories,
    queryFn: productsService.categories,
    enabled,
    staleTime: 0,
    refetchOnWindowFocus: 'always',
    refetchInterval: 30_000,
  });
}

export function useProductsById(ids: string[], enabled = true) {
  const { state } = useApp();
  const unique = [...new Set(ids)].sort();
  return useQuery({
    queryKey: queryKeys.productIds(state.currentUser?.id ?? '', unique),
    queryFn: () => productsService.getByIds(unique),
    enabled: enabled && !!state.currentUser && unique.length > 0,
    staleTime: 30_000,
  });
}
