import { useQuery } from '@tanstack/react-query';
import { supabase } from './supabase';
import { queryClient, queryKeys } from './queryClient';
import { useApp } from '../context/SupabaseAppContext';
import type { Json } from './database.types';

export const lookupKinds = [
  ['category', 'Categories'], ['size_scheme', 'Size lists'], ['brand', 'Brands'],
  ['material', 'Frame materials'], ['season', 'Model years'], ['color', 'Colors'],
  ['fit', 'Variants'], ['bank', 'Banks'], ['customer_tier', 'Customer tiers'], ['return_reason', 'Return reasons'], ['stock_reason', 'Stock adjustment reasons'],
] as const;
export type LookupKind = typeof lookupKinds[number][0];
export type LookupRow = { id: string; name: string; active: boolean; usage_count: number; description?: string; code?: string; sizes?: string[] };
export async function refreshLookups() {
  await Promise.all([
    queryClient.invalidateQueries({ queryKey: ['lookups'] }),
    queryClient.invalidateQueries({ queryKey: queryKeys.products }),
    queryClient.invalidateQueries({ queryKey: queryKeys.sizeSchemes }),
    queryClient.invalidateQueries({ queryKey: queryKeys.webCatalog }),
  ]);
}
export const lookupsService = {
  async list(kind: LookupKind) {
    const { data, error } = await supabase.rpc('list_business_lookups', { p_kind: kind });
    if (error) throw error; return data as unknown as LookupRow[];
  },
  async save(kind: LookupKind, value: Omit<LookupRow, 'id' | 'usage_count'> & { id?: string }) {
    const { error } = await supabase.rpc('save_business_lookup', { p: { ...value, kind } as Json });
    if (error) throw error; await refreshLookups();
  },
  async remove(kind: LookupKind, id: string) {
    const { error } = await supabase.rpc('delete_business_lookup', { p_kind: kind, p_id: id });
    if (error) throw error; await refreshLookups();
  },
  async choices() {
    const { data, error } = await supabase.from('business_lookups').select('kind,value').eq('active', true).order('value');
    if (error) throw error;
    const values: Record<string, string[]> = {};
    for (const row of data) (values[row.kind] ??= []).push(row.value);
    return values;
  },
};
export function useBusinessLookups(enabled = true) {
  const { state } = useApp();
  return useQuery({ queryKey: ['lookups', state.currentUser?.id, 'choices'], queryFn: lookupsService.choices, enabled: enabled && !!state.currentUser, staleTime: 0 });
}
