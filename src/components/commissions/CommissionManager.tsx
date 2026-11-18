import { useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useApp } from '../../context/SupabaseAppContext';
import { commissionsService, type CommissionPerson, type CommissionSummary } from '../../lib/commissions';
import { getErrorMessage } from '../../lib/errors';
import { rangeFor } from '../../lib/reportDates';

export function CommissionManager() {
  const { state } = useApp();
  const client = useQueryClient();
  const user = state.currentUser!;
  const manager = ['admin', 'manager'].includes(user.role);
  const [branch, setBranch] = useState('');
  const [person, setPerson] = useState('');
  const [range, setRange] = useState(() => rangeFor('this_month', new Date()));
  const [page, setPage] = useState(0);
  const branches = useQuery({ queryKey: ['commissions', user.id, 'branches'], queryFn: commissionsService.branches });
  const selectedBranch = branch || branches.data?.[0]?.id || '';
  const report = useQuery({ queryKey: ['commissions', user.id, selectedBranch, range, person, page], queryFn: () => commissionsService.overview(selectedBranch, range.from, range.to, person, page * 50), enabled: !!selectedBranch && !!range.from && !!range.to && range.from <= range.to });
  const refresh = () => client.invalidateQueries({ queryKey: ['commissions'] });
  const money = (value: number) => `${state.settings.currency} ${Number(value).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
  return <div className="space-y-5">
    <p className="text-bodytext">Assign a salesperson at checkout. Fixed commission is per invoice; percentage commission uses the amount after discounts, excluding tax and gifts. Posted credit invoices earn immediately. Partial returns reverse commission proportionally, including fixed commission.</p>
    <div className="card p-4 flex flex-wrap gap-4 items-end">
      <label className="text-sm">Branch<select className="select block" value={selectedBranch} onChange={e => { setBranch(e.target.value); setPerson(''); setPage(0); }}>
        {branches.data?.map(b => <option key={b.id} value={b.id}>{b.name}</option>)}
      </select></label>
      <label className="text-sm">From<input className="input block" type="date" value={range.from} onChange={e => { setRange({ ...range, from: e.target.value }); setPage(0); }} /></label>
      <label className="text-sm">To<input className="input block" type="date" value={range.to} onChange={e => { setRange({ ...range, to: e.target.value }); setPage(0); }} /></label>
      {manager && <label className="text-sm">Salesperson<select className="select block" value={person} onChange={e => { setPerson(e.target.value); setPage(0); }}><option value="">All salespeople</option>{report.data?.people.map(p => <option key={p.id} value={p.id}>{p.name}</option>)}</select></label>}
      <button className="btn btn-secondary" onClick={() => void refresh()} disabled={report.isFetching}>Refresh</button>
    </div>
    {range.from > range.to && <p role="alert" className="text-error">The end date must be after the start date.</p>}
    {(branches.error || report.error) && <p role="alert" className="card p-4 text-error">Could not load commissions: {getErrorMessage(branches.error || report.error)}</p>}
    {(branches.isLoading || report.isLoading) && <p role="status">Loading commissions…</p>}
    {report.data && <>
      <div className="card p-4 overflow-x-auto"><h2 className="font-semibold mb-3">Commission summary</h2><p className="text-sm text-bodytext mb-3">Earned, reversed and paid cover the selected period. Outstanding includes all dates; a negative amount carries forward after returns.</p>
        <table className="w-full text-sm"><thead><tr>{['Salesperson', 'Invoices', 'Earned', 'Returns', 'Paid', 'Outstanding (all dates)'].map(x => <th className="text-left p-2" key={x}>{x}</th>)}</tr></thead><tbody>
          {report.data.summary.map(s => <tr className="border-t border-border" key={s.user_id}><td className="p-2">{s.name}</td><td className="p-2">{s.invoices}</td><td className="p-2">{money(s.earned)}</td><td className="p-2">{money(s.reversed)}</td><td className="p-2">{money(s.paid)}</td><td className="p-2 font-semibold">{money(s.balance)}</td></tr>)}
        </tbody></table>{!report.data.summary.length && <p className="p-2 text-bodytext">No commissions recorded yet.</p>}
      </div>
      {report.data.can_manage && <>
        <details className="card p-4"><summary className="cursor-pointer font-semibold">Salesperson rules</summary><p className="text-sm text-bodytext my-3">Changes apply to future invoices. Disabling a rule keeps historical earnings. Salespeople use existing staff accounts.</p>
          <div className="space-y-3">{report.data.people.map(p => <Rule key={`${selectedBranch}:${p.id}:${p.kind}:${p.rate}:${p.enabled}`} branch={selectedBranch} initial={p} saved={refresh} currency={state.settings.currency} />)}</div>
        </details>
        <Payout key={`${user.id}:${selectedBranch}`} branch={selectedBranch} user={user.id} people={report.data.summary} money={money} saved={refresh} />
      </>}
      <div className="card p-4 overflow-x-auto"><h2 className="font-semibold mb-3">Activity</h2><table className="w-full text-sm"><thead><tr>{['Date', 'Salesperson', 'Invoice / reference', 'Activity', 'Rule at sale', 'Amount'].map(x => <th key={x} className="p-2 text-left">{x}</th>)}</tr></thead><tbody>
        {report.data.entries.map(e => <tr key={e.id} className="border-t border-border"><td className="p-2">{new Date(e.created_at).toLocaleString('en-PK', { timeZone: 'Asia/Karachi' })}</td><td className="p-2">{e.name}</td><td className="p-2">{e.invoice_number || e.note}</td><td className="p-2">{e.kind === 'earned' ? 'Earned' : e.kind === 'return' ? 'Return reversal' : 'Payout'}</td><td className="p-2">{e.rule_kind ? e.rule_kind === 'percentage' ? `${e.rule_rate}%` : `${money(e.rule_rate || 0)} / invoice` : '—'}</td><td className="p-2">{money(e.amount)}</td></tr>)}
      </tbody></table>{!report.data.entries.length && <p className="text-bodytext p-2">No activity in this period.</p>}
      <div className="flex gap-3 items-center mt-3"><button className="btn btn-secondary" disabled={!page} onClick={() => setPage(page - 1)}>Previous</button><span>{report.data.total_count} entries · Page {page + 1}</span><button className="btn btn-secondary" disabled={(page + 1) * 50 >= report.data.total_count} onClick={() => setPage(page + 1)}>Next</button></div></div>
    </>}
  </div>;
}

function Rule({ branch, initial, saved, currency }: { branch: string; initial: CommissionPerson; saved: () => Promise<unknown>; currency: string }) {
  const [rule, setRule] = useState(initial);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  return <form className="flex flex-wrap gap-3 items-end border-t border-border pt-3" onSubmit={async e => {
    e.preventDefault(); setBusy(true); setError('');
    try { await commissionsService.saveRule(branch, rule); await saved(); } catch (err) { setError(getErrorMessage(err)); } finally { setBusy(false); }
  }}>
    <span className="min-w-40 font-medium">{rule.name}{!rule.active && ' (inactive)'}</span>
    <label className="text-sm">Type<select aria-label={`Commission type for ${rule.name}`} className="select block" value={rule.kind} onChange={e => setRule({ ...rule, kind: e.target.value as CommissionPerson['kind'] })}><option value="fixed">Fixed per invoice</option><option value="percentage">Percentage</option></select></label>
    <label className="text-sm">{rule.kind === 'fixed' ? currency : 'Percent'}<input aria-label={`Commission rate for ${rule.name}`} className="input block w-32" type="number" min={rule.enabled ? '0.01' : '0'} max={rule.kind === 'percentage' ? '100' : '999999999999'} step="0.01" required value={rule.rate} onChange={e => setRule({ ...rule, rate: Number(e.target.value) })} /></label>
    <label className="flex gap-2 items-center"><input type="checkbox" checked={rule.enabled} disabled={!rule.active && !rule.enabled} onChange={e => setRule({ ...rule, enabled: e.target.checked })} />Enabled</label>
    <button className="btn btn-primary" disabled={busy}>{busy ? 'Saving…' : 'Save rule'}</button>{error && <p role="alert" className="text-error">{error}</p>}
  </form>;
}

type PendingPayout = { branch: string; person: string; amount: number; note: string; requestId: string };
function Payout({ branch, user, people, money, saved }: { branch: string; user: string; people: CommissionSummary[]; money: (n: number) => string; saved: () => Promise<unknown> }) {
  const key = `commission.pendingPayout:${user}`;
  const [person, setPerson] = useState(''); const [amount, setAmount] = useState(''); const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false); const [message, setMessage] = useState('');
  const [pending, setPending] = useState<PendingPayout | null>(() => { try { const p = JSON.parse(sessionStorage.getItem(key) || 'null'); return p && typeof p.requestId === 'string' && typeof p.branch === 'string' && typeof p.person === 'string' && typeof p.amount === 'number' && Number.isFinite(p.amount) && typeof p.note === 'string' ? p : null; } catch { return null; } });
  return <details className="card p-4" open={pending ? true : undefined}><summary className="font-semibold cursor-pointer">Record commission payout</summary><p className="my-3 text-sm text-bodytext">Record money already paid to staff. This does not transfer money or withdraw cash from a till.</p>
    {pending && <p role="status" className="mb-3 text-warning">An unconfirmed payout is saved: {money(pending.amount)} · {pending.note}. Retry it to confirm before recording another.{pending.branch !== branch && ' Switch to its original branch to retry.'}</p>}
    <form className="flex flex-wrap gap-3 items-end" onSubmit={async e => {
      e.preventDefault(); setMessage(''); setBusy(true);
      try {
        const record = pending || { branch, person, amount: Number(amount), note: note.trim(), requestId: crypto.randomUUID() };
        if (record.branch !== branch) throw new Error('Choose the original payout branch first.');
        sessionStorage.setItem(key, JSON.stringify(record)); setPending(record);
        await commissionsService.payout(record);
        sessionStorage.removeItem(key); setPending(null); setAmount(''); setNote(''); setMessage('Payout recorded.'); await saved();
      } catch (err) { setMessage(getErrorMessage(err)); } finally { setBusy(false); }
    }}>
      {!pending && <><label className="text-sm">Salesperson<select className="select block" required value={person} onChange={e => setPerson(e.target.value)}><option value="">Choose salesperson</option>{people.filter(p => p.balance > 0).map(p => <option key={p.user_id} value={p.user_id}>{p.name} · {money(p.balance)}</option>)}</select></label>
      <label className="text-sm">Amount<input className="input block w-36" type="number" step="0.01" min="0.01" max={people.find(p => p.user_id === person)?.balance} value={amount} onChange={e => setAmount(e.target.value)} required /></label>
      <label className="text-sm">Payment reference<input className="input block" maxLength={500} value={note} onChange={e => setNote(e.target.value)} required /></label></>}
      <button className="btn btn-primary" disabled={busy || (!!pending && pending.branch !== branch)}>{busy ? 'Confirming…' : pending ? 'Retry saved payout' : 'Record payment already made'}</button>
      {pending && <button type="button" className="btn btn-secondary" disabled={busy} onClick={async () => {
        if (!window.confirm('Only clear this saved request after checking commission activity to confirm whether it was recorded. Clear it?')) return;
        sessionStorage.removeItem(key); setPending(null); setMessage('Saved request cleared.'); await saved();
      }}>Clear reconciled request</button>}
    </form>{message && <p role="status" className="mt-3">{message}</p>}
  </details>;
}
