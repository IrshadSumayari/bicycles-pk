import { useState, type FormEvent } from 'react';
import { useQuery } from '@tanstack/react-query';
import { useApp } from '../../context/SupabaseAppContext';
import { lookupKinds, lookupsService, type LookupKind, type LookupRow } from '../../lib/lookups';
import { getErrorMessage } from '../../lib/errors';

export function LookupManager() {
  const { state } = useApp();
  const [kind, setKind] = useState<LookupKind>('category');
  const [search, setSearch] = useState('');
  const [editing, setEditing] = useState<LookupRow | null | undefined>();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [page, setPage] = useState(0);
  const query = useQuery({ queryKey: ['lookups', state.currentUser?.id, 'manage', kind], queryFn: () => lookupsService.list(kind) });
  const rows = (query.data || []).filter(r => `${r.name} ${r.code || ''}`.toLowerCase().includes(search.toLowerCase()));
  async function remove(row: LookupRow) {
    if (!window.confirm(`Delete "${row.name}"? This only removes the unused lookup.`)) return;
    setBusy(true); setError('');
    try { await lookupsService.remove(kind, row.id); } catch (err) { setError(getErrorMessage(err)); } finally { setBusy(false); }
  }
  return <section className="card p-5 space-y-4" aria-label="Lookup management">
    <h2 className="text-xl font-semibold">Lookups</h2>
    <p className="text-bodytext text-sm">Manage the choices used in your shop. Delete unused values; deactivate values that are still used. Existing products and transaction history are preserved.</p>
    <div className="flex flex-wrap gap-3 items-end">
      <label className="text-sm">Lookup<select className="select block" value={kind} disabled={busy} onChange={e => { setKind(e.target.value as LookupKind); setEditing(undefined); setSearch(''); setPage(0); setError(''); }}>{lookupKinds.map(([id, label]) => <option key={id} value={id}>{label}</option>)}</select></label>
      <label className="text-sm">Search<input className="input block" value={search} onChange={e => { setSearch(e.target.value); setPage(0); }} /></label>
      <button type="button" className="btn btn-primary" disabled={busy} onClick={() => setEditing(null)}>Add value</button>
      <button type="button" className="btn btn-secondary" onClick={() => void query.refetch()} disabled={query.isFetching}>Refresh</button>
    </div>
    {query.isLoading && <p role="status">Loading lookups…</p>}
    {(error || query.error) && <p role="alert" className="text-error">{error || getErrorMessage(query.error)}</p>}
    <div className="overflow-x-auto"><table className="table w-full text-sm"><thead><tr>{['Name', ...(kind === 'size_scheme' ? ['Code / sizes'] : []), 'Status', 'Used by', 'Actions'].map(t => <th key={t} className="table-cell text-left">{t}</th>)}</tr></thead><tbody>
      {rows.slice(page * 50, (page + 1) * 50).map(row => <tr key={row.id} className="border-t border-border"><td className="table-cell">{row.name}</td>{kind === 'size_scheme' && <td className="table-cell">{row.code}: {row.sizes?.join(', ')}</td>}<td className="table-cell">{row.active ? 'Active' : 'Inactive'}</td><td className="table-cell">{row.usage_count} records</td><td className="table-cell"><div className="flex flex-wrap gap-2">
        <button type="button" className="btn btn-secondary btn-sm" disabled={busy} onClick={() => setEditing(row)}>Edit</button>
        <button type="button" className="btn btn-secondary btn-sm" disabled={busy} onClick={async () => { setBusy(true); setError(''); try { await lookupsService.save(kind, { ...row, active: !row.active }); } catch (err) { setError(getErrorMessage(err)); } finally { setBusy(false); } }}>{row.active ? 'Deactivate' : 'Activate'}</button>
        <button type="button" className="btn btn-secondary btn-sm" disabled={busy || row.usage_count > 0} title={row.usage_count ? 'In use: deactivate, or reassign its records before deleting' : 'Delete unused lookup'} onClick={() => void remove(row)}>Delete</button>
      </div></td></tr>)}
    </tbody></table>{!query.isLoading && !rows.length && <p className="p-3 text-bodytext">No values yet. Add your own shop’s choices.</p>}</div>
    {rows.length > 50 && <div className="flex gap-3 items-center"><button type="button" className="btn btn-secondary" disabled={!page} onClick={() => setPage(page - 1)}>Previous</button><span>{rows.length} values · Page {page + 1}</span><button type="button" className="btn btn-secondary" disabled={(page + 1) * 50 >= rows.length} onClick={() => setPage(page + 1)}>Next</button></div>}
    <p className="text-xs text-bodytext">Payment methods, staff roles, stock units and order statuses are system rules. Standard is the default customer tier; Other allows a free-text reason. These built-in fallbacks remain available.</p>
    {editing !== undefined && <LookupEditor key={`${kind}:${editing?.id || 'new'}`} kind={kind} initial={editing} close={() => setEditing(undefined)} />}
  </section>;
}

function LookupEditor({ kind, initial, close }: { kind: LookupKind; initial: LookupRow | null; close: () => void }) {
  const [name, setName] = useState(initial?.name || '');
  const [description, setDescription] = useState(initial?.description || '');
  const [code, setCode] = useState(initial?.code || '');
  const [sizes, setSizes] = useState(initial?.sizes?.join(', ') || '');
  const [active, setActive] = useState(initial?.active ?? true);
  const [saving, setSaving] = useState(false); const [error, setError] = useState('');
  async function save(e: FormEvent) {
    e.preventDefault(); setSaving(true); setError('');
    try { await lookupsService.save(kind, { id: initial?.id, name: name.trim(), description, code: code.trim(), sizes: sizes.split(',').map(x => x.trim()).filter(Boolean), active }); close(); }
    catch (err) { setError(getErrorMessage(err)); } finally { setSaving(false); }
  }
  return <div className="modal-overlay" role="dialog" aria-modal="true" aria-label="Lookup editor"><form className="modal max-w-xl w-full" onSubmit={save}><div className="modal-header"><h3 className="font-semibold text-lg">{initial ? 'Edit' : 'Add'} lookup</h3></div>
    <fieldset className="modal-body space-y-4" disabled={saving}>
      <label className="block text-sm">Name<input className="input block" value={name} onChange={e => setName(e.target.value)} maxLength={200} required autoFocus /></label>
      {kind === 'category' && <label className="block text-sm">Description<textarea className="textarea block w-full" value={description} maxLength={2000} onChange={e => setDescription(e.target.value)} /></label>}
      {kind === 'size_scheme' && <><label className="block text-sm">Code<input className="input block" value={code} onChange={e => setCode(e.target.value.toUpperCase())} pattern="[A-Z0-9][A-Z0-9_-]{0,39}" maxLength={40} required /></label><label className="block text-sm">Sizes, separated by commas<input className="input block" value={sizes} onChange={e => setSizes(e.target.value)} required /><span className="text-xs text-bodytext">Keep them in the order you want to use when building variants.</span></label></>}
      <label className="flex gap-2 items-center"><input type="checkbox" checked={active} onChange={e => setActive(e.target.checked)} />Active</label>
      {initial && <p className="text-xs text-bodytext">Renaming a category, brand, frame material, model year, colour or variant updates current catalog records. Posted sale and payment history remains unchanged.</p>}
      {error && <p role="alert" className="text-error">{error}</p>}
    </fieldset><div className="modal-footer flex gap-3"><button type="button" className="btn btn-secondary" disabled={saving} onClick={close}>Cancel</button><button className="btn btn-primary" disabled={saving}>{saving ? 'Saving…' : 'Save lookup'}</button></div>
  </form></div>;
}
