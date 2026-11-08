import { useRef, useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { Input } from '@/components/ui/input';
import { useApp } from '../../context/SupabaseAppContext';
import { getErrorMessage } from '../../lib/errors';
import { marketingService, marketingCsv, type MarketingChannel, type CampaignDraft } from '../../lib/marketing';

const empty = (): Pick<CampaignDraft, 'id' | 'name' | 'channel' | 'subject' | 'body'> => ({ id: crypto.randomUUID(), name: '', channel: 'email', subject: '', body: '' });
export function MarketingPanel() {
  const { state } = useApp();
  const client = useQueryClient();
  const [channel, setChannel] = useState<MarketingChannel>('email');
  const [offset, setOffset] = useState(0);
  const [draft, setDraft] = useState(empty);
  const [message, setMessage] = useState('');
  const [busy, setBusy] = useState(false);
  const pending = useRef(false);
  const allowed = ['admin', 'manager'].includes(state.currentUser?.role ?? '');
  const key = ['marketing', state.currentUser?.id];
  const audience = useQuery({ queryKey: [...key, 'audience', channel, offset], queryFn: () => marketingService.audience(channel, '', offset), enabled: allowed });
  const drafts = useQuery({ queryKey: [...key, 'drafts'], queryFn: marketingService.drafts, enabled: allowed });
  if (!allowed) return null;
  async function save(event: React.FormEvent) {
    event.preventDefault();
    if (pending.current) return;
    pending.current = true; setBusy(true); setMessage('');
    try {
      if (!draft.name.trim() || !draft.body.trim() || (draft.channel === 'email' && !draft.subject.trim())) throw new Error('Enter a campaign name, message and email subject.');
      await marketingService.save({ ...draft, name: draft.name.trim(), subject: draft.subject.trim(), body: draft.body.trim() });
      await client.invalidateQueries({ queryKey: [...key, 'drafts'] });
      setMessage('Draft saved. No messages have been sent.');
    } catch (error) { setMessage(getErrorMessage(error)); }
    finally { pending.current = false; setBusy(false); }
  }
  async function exportPage() {
    setBusy(true); setMessage('');
    try {
      // Re-query at export time so an old cached screen does not export withdrawn consent.
      const rows = await marketingService.audience(channel, '', offset);
      if (!rows.length) throw new Error('No eligible contacts on this page.');
      const url = URL.createObjectURL(new Blob([marketingCsv(rows)], { type: 'text/csv;charset=utf-8;' }));
      const a = document.createElement('a'); a.href = url; a.download = `bicycles-${channel}-contacts-page-${offset / 50 + 1}.csv`; a.click(); URL.revokeObjectURL(url);
      setMessage(`Exported ${rows.length} contacts from this page. Recheck consent before a future send.`);
    } catch (error) { setMessage(getErrorMessage(error)); }
    finally { setBusy(false); }
  }
  return <section className="space-y-6" aria-label="Customer promotions">
    <div className="card p-5 space-y-3"><h2 className="text-xl font-bold">Promotional email &amp; SMS</h2>
      <p>Prepare campaigns for customers who agreed to receive offers. Sending will be available after your email and SMS providers are connected.</p>
      <p className="text-sm text-bodytext">Saving a contact does not subscribe them. Any recorded opt-out for the same destination excludes it from this list, including across POS and website profiles.</p>
    </div>
    <div className="card p-5 space-y-4">
      <div className="flex flex-wrap gap-3 items-center"><h3 className="font-semibold">Eligible recipients</h3>
        <select aria-label="Recipient channel" className="select w-auto" value={channel} onChange={e => { setChannel(e.target.value as MarketingChannel); setOffset(0); }}><option value="email">Email</option><option value="sms">SMS</option></select>
        <button className="btn btn-secondary btn-sm" disabled={busy || audience.isFetching} onClick={() => void audience.refetch()}>Refresh</button>
        <button className="btn btn-secondary btn-sm" disabled={busy || !audience.data?.length} onClick={() => void exportPage()}>Export this page (CSV)</button>
      </div>
      {audience.isPending && <p role="status">Loading recipients...</p>}
      {audience.error && <p role="alert">{getErrorMessage(audience.error)}</p>}
      <p>{audience.data?.[0]?.total_count ?? 0} eligible contacts. Showing up to 50 on this page.</p>
      <div className="overflow-x-auto"><table className="table"><thead><tr><th>Name</th><th>Contact</th><th>Source</th><th>Consent recorded</th></tr></thead><tbody>{audience.data?.map(r => <tr key={r.contact}><td className="table-cell">{r.name}</td><td className="table-cell">{r.contact}</td><td className="table-cell">{r.source}</td><td className="table-cell">{r.consent_at ? new Date(r.consent_at).toLocaleString() : '-'}</td></tr>)}</tbody></table></div>
      {!audience.isPending && !audience.error && !audience.data?.length && <p>No opted-in contacts here. Record preferences in the customer form or website profile.</p>}
      <div className="flex gap-3"><button className="btn btn-secondary btn-sm" disabled={!offset || audience.isFetching} onClick={() => setOffset(Math.max(0, offset - 50))}>Previous</button><button className="btn btn-secondary btn-sm" disabled={audience.isFetching || offset + 50 >= (audience.data?.[0]?.total_count ?? 0)} onClick={() => setOffset(offset + 50)}>Next</button></div>
    </div>
    <form className="card p-5 space-y-4" onSubmit={save}>
      <h3 className="font-semibold">Campaign draft</h3><fieldset disabled={busy} className="space-y-4">
        <label className="block">Campaign name<Input className="input" required maxLength={150} value={draft.name} onChange={e => setDraft({ ...draft, name: e.target.value })} /></label>
        <label className="block">Channel<select className="select" value={draft.channel} onChange={e => setDraft({ ...draft, channel: e.target.value as MarketingChannel })}><option value="email">Email</option><option value="sms">SMS</option></select></label>
        {draft.channel === 'email' && <label className="block">Subject<Input className="input" required maxLength={200} value={draft.subject} onChange={e => setDraft({ ...draft, subject: e.target.value })} /></label>}
        <label className="block">Message<textarea className="textarea" required rows={5} maxLength={10000} value={draft.body} onChange={e => setDraft({ ...draft, body: e.target.value })} /></label>
        <p className="text-sm text-bodytext">{draft.body.length} characters. SMS segment counts, sender identity and unsubscribe handling will be verified with your provider.</p>
        <div className="flex gap-3"><button className="btn btn-primary btn-md" type="submit">Save draft</button><button className="btn btn-secondary btn-md" type="button" onClick={() => setDraft(empty())}>New draft</button></div>
      </fieldset>
    </form>
    {message && <p role="status" className="card p-4">{message}</p>}
    <div className="card p-5 space-y-3"><h3 className="font-semibold">Saved drafts (latest 100)</h3>
      {drafts.error && <p role="alert">{getErrorMessage(drafts.error)}</p>}
      {drafts.isPending && <p>Loading drafts...</p>}
      {drafts.data?.map((item: CampaignDraft) => <button className="btn btn-secondary btn-md mr-2" key={item.id} onClick={() => { setDraft(item); setMessage(''); }}>{item.name} · {item.channel} · Draft</button>)}
      {drafts.data?.length === 0 && <p>No saved campaigns yet.</p>}
    </div>
  </section>;
}
