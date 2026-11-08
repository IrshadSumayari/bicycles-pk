import { useEffect, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { useApp } from '../../context/SupabaseAppContext';
import { customersService } from '../services';
import { queryKeys } from '../queryClient';

export function useCustomerSearchText(value: string) {
  const [debounced, setDebounced] = useState(value.trim());
  useEffect(() => {
    const timer = setTimeout(() => setDebounced(value.trim()), 300);
    return () => clearTimeout(timer);
  }, [value]);
  return debounced;
}

export function useCustomerSearch(q: string) {
  const { state } = useApp();
  const term = useCustomerSearchText(q);
  const query = useQuery({
    queryKey: queryKeys.customerSearch(state.currentUser?.id ?? '', term),
    queryFn: () => customersService.search(term),
    enabled: !!state.currentUser && !!term && q.trim() === term,
  });
  const debouncing = q.trim() !== term;
  return {
    ...query,
    data: debouncing || !q.trim() ? [] : query.data,
    searching: !!q.trim() && (debouncing || query.isFetching),
  };
}
