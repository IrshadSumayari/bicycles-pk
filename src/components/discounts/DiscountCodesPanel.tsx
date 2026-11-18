import { useEffect, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Copy, Edit, Plus, Ticket, X } from 'lucide-react';
import { Input } from '@/components/ui/input';
import { DataTable } from '@/components/shared/DataTable';
import { ModalShell } from '@/components/shared/ModalShell';
import { useApp } from '../../context/SupabaseAppContext';
import { queryKeys } from '../../lib/queryClient';
import {
  CodeDiscountType, DiscountCodeRow, WelcomeSettings, describeOffer, discountCodesService, formatCodeDate,
} from '../../lib/discountCodes';
import { getErrorMessage } from '../../lib/errors';
import { swalConfig } from '../../lib/sweetAlert';

const STATUS_BADGE = {
  ready: ['badge-success', 'Ready'], used: ['badge-secondary', 'Used up'], expired: ['badge-danger', 'Expired'],
  scheduled: ['badge-info', 'Not started'], off: ['badge-warning', 'Switched off'],
} as const;

const num = (value: string) => (value.trim() === '' ? null : Number(value));
const dateInput = (iso: string | null) => (iso ? iso.slice(0, 10) : '');

// Welcome-code settings and the list of all codes (admins and managers)
export function DiscountCodesPanel() {
  const { state } = useApp();
  const currency = state.settings.currency;
  const settingsQuery = useQuery({ queryKey: queryKeys.discountCodeSettings, queryFn: discountCodesService.settings });
  const codesQuery = useQuery({ queryKey: queryKeys.discountCodes, queryFn: discountCodesService.list });
  const [editing, setEditing] = useState<DiscountCodeRow | 'new' | null>(null);
  const [search, setSearch] = useState('');

  const codes = (codesQuery.data ?? []).filter(c => {
    const q = search.trim().toLowerCase();
    return !q || c.code.toLowerCase().includes(q) || (c.customer?.name ?? '').toLowerCase().includes(q)
      || (c.customer?.phone ?? '').includes(q) || (c.description ?? '').toLowerCase().includes(q);
  });

  const toggle = async (code: DiscountCodeRow) => {
    try {
      await discountCodesService.save({
        id: code.id, code: code.code, description: code.description ?? undefined, customer_id: code.customer_id,
        discount_type: code.discount_type, value: code.value, min_amount: code.min_amount, max_discount: code.max_discount,
        valid_from: code.valid_from, expires_at: code.expires_at, max_uses: code.max_uses, active: !code.active,
      });
    } catch (e) {
      swalConfig.error(getErrorMessage(e));
    }
  };

  return (
    <div className="space-y-6">
      {settingsQuery.data && <WelcomeSettingsCard initial={settingsQuery.data} />}
      {settingsQuery.error && <p className="text-sm text-error">{getErrorMessage(settingsQuery.error)}</p>}

      <div className="card p-4 lg:p-6 space-y-4">
        <div className="flex flex-col sm:flex-row justify-between gap-4">
          <div>
            <h3 className="font-semibold text-link flex items-center gap-2"><Ticket className="h-5 w-5" />Discount codes</h3>
            <p className="text-sm text-bodytext">Customers give the code at the counter. Welcome codes are personal and used once.</p>
          </div>
          <button type="button" className="btn btn-primary btn-md" onClick={() => setEditing('new')}>
            <Plus className="h-4 w-4" /><span>Create code</span>
          </button>
        </div>
        <Input value={search} onChange={e => setSearch(e.target.value)} placeholder="Search code, customer or phone" className="input max-w-md" />
        {codesQuery.error && <p className="text-sm text-error">{getErrorMessage(codesQuery.error)}</p>}
        <DataTable className="table" empty={codesQuery.isPending ? undefined : codes.length ? undefined : 'No discount codes yet'}>
          <thead className="table-header">
            <tr>
              <th className="table-header-cell">Code</th>
              <th className="table-header-cell">Offer</th>
              <th className="table-header-cell">For</th>
              <th className="table-header-cell">Used</th>
              <th className="table-header-cell">Valid until</th>
              <th className="table-header-cell">Status</th>
              <th className="table-header-cell text-right">Actions</th>
            </tr>
          </thead>
          <tbody className="bg-card divide-y divide-border">
            {codes.map(code => (
              <tr key={code.id} className="table-row">
                <td className="table-cell">
                  <div className="font-mono font-semibold">{code.code}</div>
                  <div className="text-xs text-bodytext">{code.kind === 'welcome' ? 'Welcome code' : code.description}</div>
                </td>
                <td className="table-cell text-sm">{describeOffer(code, currency)}</td>
                <td className="table-cell text-sm">{code.customer ? `${code.customer.name}${code.customer.phone ? ` · ${code.customer.phone}` : ''}` : 'Anyone'}</td>
                <td className="table-cell text-sm">{code.used_count}{code.max_uses ? ` of ${code.max_uses}` : ''}</td>
                <td className="table-cell text-sm">{formatCodeDate(code.expires_at)}</td>
                <td className="table-cell">
                  <button type="button" onClick={() => void toggle(code)} title={code.active ? 'Switch off' : 'Switch on'}
                          className={`badge ${STATUS_BADGE[code.status][0]} cursor-pointer hover:opacity-80`}>
                    {STATUS_BADGE[code.status][1]}
                  </button>
                </td>
                <td className="table-cell text-right">
                  <div className="flex items-center justify-end gap-1">
                    <button type="button" title="Copy code" onClick={() => void navigator.clipboard?.writeText(code.code).then(() => swalConfig.success(`${code.code} copied`))}
                            className="text-primary p-2 rounded-lg hover:bg-lightprimary"><Copy className="h-4 w-4" /></button>
                    <button type="button" title="Edit" onClick={() => setEditing(code)}
                            className="text-primary p-2 rounded-lg hover:bg-lightprimary"><Edit className="h-4 w-4" /></button>
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </DataTable>
      </div>

      {editing && <CodeModal code={editing === 'new' ? null : editing} onClose={() => setEditing(null)} />}
    </div>
  );
}

function WelcomeSettingsCard({ initial }: { initial: WelcomeSettings }) {
  const { state } = useApp();
  const [form, setForm] = useState({
    enabled: initial.welcome_enabled,
    type: initial.welcome_type,
    value: String(initial.welcome_value),
    days: String(initial.welcome_valid_days),
    min: initial.welcome_min_amount === null ? '' : String(initial.welcome_min_amount),
    max: initial.welcome_max_discount === null ? '' : String(initial.welcome_max_discount),
  });
  const [saving, setSaving] = useState(false);
  const set = (changes: Partial<typeof form>) => setForm(prev => ({ ...prev, ...changes }));

  const save = async () => {
    setSaving(true);
    try {
      await discountCodesService.saveSettings({
        welcome_enabled: form.enabled, welcome_type: form.type, welcome_value: Number(form.value),
        welcome_valid_days: Number(form.days), welcome_min_amount: num(form.min), welcome_max_discount: num(form.max),
      });
      swalConfig.success('Welcome code settings saved');
    } catch (e) {
      swalConfig.error(getErrorMessage(e));
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="card p-4 lg:p-6 space-y-4">
      <div>
        <h3 className="font-semibold text-link">Welcome code for new customers</h3>
        <p className="text-sm text-bodytext">
          When on, every new customer gets a personal one-time code. Changes apply to codes given from now on; codes already given keep their offer.
        </p>
      </div>
      <label className="flex items-center gap-2 text-sm font-medium">
        <input type="checkbox" checked={form.enabled} onChange={e => set({ enabled: e.target.checked })} />
        Give new customers a welcome code
      </label>
      <div className="grid grid-cols-2 lg:grid-cols-5 gap-3">
        <label className="block text-sm">Discount type
          <select className="select" value={form.type} onChange={e => set({ type: e.target.value as CodeDiscountType })}>
            <option value="percentage">Percent off</option>
            <option value="fixed">Amount off ({state.settings.currency})</option>
          </select>
        </label>
        <label className="block text-sm">{form.type === 'percentage' ? 'Percent' : 'Amount'}
          <Input type="number" min="0" step="0.01" className="input" value={form.value} onChange={e => set({ value: e.target.value })} />
        </label>
        <label className="block text-sm">Valid for (days)
          <Input type="number" min="1" step="1" className="input" value={form.days} onChange={e => set({ days: e.target.value })} />
        </label>
        <label className="block text-sm">Minimum spend (optional)
          <Input type="number" min="0" step="0.01" className="input" value={form.min} onChange={e => set({ min: e.target.value })} />
        </label>
        {form.type === 'percentage' && (
          <label className="block text-sm">Most it can take off (optional)
            <Input type="number" min="0" step="0.01" className="input" value={form.max} onChange={e => set({ max: e.target.value })} />
          </label>
        )}
      </div>
      <button type="button" className="btn btn-primary btn-md" disabled={saving} onClick={() => void save()}>
        {saving ? 'Saving...' : 'Save welcome settings'}
      </button>
    </div>
  );
}

function CodeModal({ code, onClose }: { code: DiscountCodeRow | null; onClose: () => void }) {
  const { state } = useApp();
  const welcome = code?.kind === 'welcome';
  const [form, setForm] = useState({
    code: code?.code ?? '', description: code?.description ?? '', type: code?.discount_type ?? 'percentage' as CodeDiscountType,
    value: code ? String(code.value) : '', min: code?.min_amount == null ? '' : String(code.min_amount),
    max: code?.max_discount == null ? '' : String(code.max_discount), from: dateInput(code?.valid_from ?? null),
    to: dateInput(code?.expires_at ?? null), uses: code ? (code.max_uses === null ? '' : String(code.max_uses)) : '1',
  });
  const [saving, setSaving] = useState(false);
  const set = (changes: Partial<typeof form>) => setForm(prev => ({ ...prev, ...changes }));
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);

  const save = async () => {
    setSaving(true);
    try {
      // Dates are whole days in the shop's time: from the start of the first day to the end of the last
      const saved = await discountCodesService.save({
        id: code?.id, code: form.code, description: form.description, customer_id: code?.customer_id ?? null,
        discount_type: form.type, value: Number(form.value), min_amount: num(form.min), max_discount: num(form.max),
        valid_from: form.from ? `${form.from}T00:00:00+05:00` : code?.valid_from ?? null,
        expires_at: form.to ? `${form.to}T23:59:59+05:00` : null,
        max_uses: num(form.uses), active: code?.active ?? true,
      });
      swalConfig.success(`Code ${saved.code} saved`);
      onClose();
    } catch (e) {
      swalConfig.error(getErrorMessage(e));
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="modal-overlay">
      <ModalShell className="modal max-w-lg">
        <div className="modal-header">
          <h2 className="text-xl font-bold text-link">{code ? `Edit ${code.code}` : 'Create discount code'}</h2>
          <button type="button" onClick={onClose} className="p-2 rounded-xl hover:bg-lightgray"><X className="h-6 w-6" /></button>
        </div>
        <div className="modal-body space-y-4">
          <label className="block text-sm">Code
            <Input className="input font-mono uppercase" value={form.code} maxLength={24} disabled={!!code && code.used_count > 0}
                   onChange={e => set({ code: e.target.value.toUpperCase().replace(/[^A-Z0-9-]/g, '') })}
                   placeholder="Leave empty to make one, e.g. LV-7KQ2XH" />
          </label>
          {!welcome && (
            <label className="block text-sm">Note for staff (optional)
              <Input className="input" value={form.description} onChange={e => set({ description: e.target.value })} placeholder="e.g. Independence Day sale" />
            </label>
          )}
          <div className="grid grid-cols-2 gap-3">
            <label className="block text-sm">Discount type
              <select className="select" value={form.type} onChange={e => set({ type: e.target.value as CodeDiscountType })}>
                <option value="percentage">Percent off</option>
                <option value="fixed">Amount off ({state.settings.currency})</option>
              </select>
            </label>
            <label className="block text-sm">{form.type === 'percentage' ? 'Percent' : 'Amount'}
              <Input type="number" min="0" step="0.01" className="input" value={form.value} onChange={e => set({ value: e.target.value })} />
            </label>
            <label className="block text-sm">Minimum spend (optional)
              <Input type="number" min="0" step="0.01" className="input" value={form.min} onChange={e => set({ min: e.target.value })} />
            </label>
            {form.type === 'percentage' && (
              <label className="block text-sm">Most it can take off (optional)
                <Input type="number" min="0" step="0.01" className="input" value={form.max} onChange={e => set({ max: e.target.value })} />
              </label>
            )}
            <label className="block text-sm">Starts (optional)
              <Input type="date" className="input" value={form.from} onChange={e => set({ from: e.target.value })} />
            </label>
            <label className="block text-sm">Last day (optional)
              <Input type="date" className="input" value={form.to} onChange={e => set({ to: e.target.value })} />
            </label>
            {!welcome && (
              <label className="block text-sm">Number of uses
                <Input type="number" min="1" step="1" className="input" value={form.uses} onChange={e => set({ uses: e.target.value })} placeholder="Empty: unlimited" />
              </label>
            )}
          </div>
        </div>
        <div className="modal-footer">
          <button type="button" className="btn btn-secondary btn-md" onClick={onClose}>Cancel</button>
          <button type="button" className="btn btn-primary btn-md" disabled={saving || !form.value} onClick={() => void save()}>
            {saving ? 'Saving...' : 'Save code'}
          </button>
        </div>
      </ModalShell>
    </div>
  );
}
