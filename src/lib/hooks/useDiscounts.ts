import { useQuery } from '@tanstack/react-query';
import { useApp } from '../../context/SupabaseAppContext';
import { discountsService } from '../services';
import { queryKeys } from '../queryClient';

export function useDiscounts() {
  const { state } = useApp();
  return useQuery({
    queryKey: queryKeys.discountList(state.currentUser?.id ?? ''),
    queryFn: discountsService.getAll,
    enabled: ['admin', 'manager'].includes(state.currentUser?.role ?? ''),
  });
}
