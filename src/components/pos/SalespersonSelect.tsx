import { useQuery } from '@tanstack/react-query';
import { commissionsService } from '../../lib/commissions';
import { useApp } from '../../context/SupabaseAppContext';

export function SalespersonSelect({ branch, value, onChange, disabled }: { branch?: string; value: string; onChange: (id: string) => void; disabled?: boolean }) {
  const { state } = useApp();
  const sellers = useQuery({ queryKey: ['commissions', state.currentUser?.id, 'sellers', branch], queryFn: () => commissionsService.sellers(branch!), enabled: !!branch, staleTime: 0 });
  return <div className="space-y-1">
    <label className="block text-sm font-medium">Salesperson (commission)
      <select className="select block w-full mt-1" value={value} disabled={disabled || !branch || sellers.isFetching} onChange={e => onChange(e.target.value)}>
        <option value="">No salesperson commission</option>
        {value && !sellers.data?.some(s => s.id === value) && <option value={value}>Previously selected salesperson — refresh required</option>}
        {sellers.data?.map(s => <option key={s.id} value={s.id}>{s.name}</option>)}
      </select>
    </label>
    <p className="text-xs text-bodytext">Select the person who made this sale. Managers configure eligible staff under Commissions.</p>
    {sellers.error && <p role="alert" className="text-sm text-error">Salespeople could not be loaded. Refresh before assigning commission.</p>}
  </div>;
}
