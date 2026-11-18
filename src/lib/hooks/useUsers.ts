import { useQuery } from '@tanstack/react-query';
import { useApp } from '../../context/SupabaseAppContext';
import { usersService } from '../services';
import { queryKeys } from '../queryClient';

export function useUsers(enabled = true) {
  const { state } = useApp();
  return useQuery({
    queryKey: queryKeys.userList(state.currentUser?.id ?? ''),
    queryFn: usersService.getAll,
    enabled:
      enabled && ['admin', 'manager'].includes(state.currentUser?.role ?? ''),
  });
}
