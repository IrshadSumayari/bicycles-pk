import {Input}from'@/components/ui/input';
import {DataTable}from'@/components/shared/DataTable';
import { useProductSearch, useProductsById } from '../../lib/hooks/useProducts';
import { ReportStatus } from '../reports/ReportStatus';
import { queryKeys } from '../../lib/queryClient';
import React, { useRef, useState } from 'react';
import { ClipboardCheck, XCircle } from 'lucide-react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { Product, productLabel } from '../../types';
import { useApp } from '../../context/SupabaseAppContext';
import { productsService, countsService } from '../../lib/services';
import { swalConfig } from '../../lib/sweetAlert';
import { getErrorMessage } from '../../lib/errors';

// Count the shop floor: scan or search an item, type what is on the shelf.
// The system quantity is taken when each item is counted; a manager approves
// and the differences are posted to the stock ledger.
export function StockCountPanel() {
  const { state } = useApp();
  const queryClient = useQueryClient();
  const [search, setSearch] = useState('');
  const [selected, setSelected] = useState<Product | null>(null);
  const [counted, setCounted] = useState('');
  const [busy, setBusy] = useState(false);
  const countedRef = useRef<HTMLInputElement>(null);

  const { data: counts = [] } = useQuery({ queryKey: queryKeys.stockCounts, queryFn: () => countsService.list() });
  const openCount = counts.find(c => c.status === 'open');

  const { data: lines = [] } = useQuery({
    queryKey: queryKeys.stockCountLines(openCount?.id),
    queryFn: () => countsService.lines(openCount!.id),
    enabled: !!openCount,
  });

  const saved = useProductsById(lines.map(line => line.variantId));
  const products = new Map((saved.data ?? []).map(product => [product.id, product]));
  const query = useProductSearch({ q: search, limit: 20 }, !!search.trim() && !selected);
  const matches = !selected && search.trim() ? (query.data?.rows ?? []).filter(p => p.trackInventory && p.kind !== 'service') : [];

  const choose = (product: Product) => {
    setSelected(product);
    setSearch(productLabel(product));
    setCounted('');
    setTimeout(() => countedRef.current?.focus(), 0);
  };

  const handleSearchKey = async (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key !== 'Enter') return;
    e.preventDefault();
    const code = search.trim().toUpperCase();
    let exact: Product | null = null;
    try { exact = await productsService.byCode(code); }
    catch (error) { swalConfig.error(getErrorMessage(error)); }
    if (exact && (!exact.trackInventory || exact.kind === 'service')) return;
    if (exact) choose(exact);
    else if (!query.searching && !query.isPlaceholderData && matches.length === 1) choose(matches[0]);
  };

  const reset = () => {
    setSelected(null);
    setSearch('');
    setCounted('');
  };

  const refreshCount = () => queryClient.invalidateQueries({ queryKey: queryKeys.stockCountLines(openCount?.id) });

  const handleStart = async () => {
    setBusy(true);
    try {
      await countsService.start();
      await queryClient.invalidateQueries({ queryKey: queryKeys.stockCounts });
    } catch (error) {
      swalConfig.error(`Could not start the count: ${getErrorMessage(error)}`);
    } finally {
      setBusy(false);
    }
  };

  const handleRecord = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!openCount || !selected) return;
    const qty = Number(counted);
    if (counted === '' || !Number.isFinite(qty) || qty < 0 || !Number.isInteger(qty)) {
      swalConfig.error('Enter a whole number');
      return;
    }
    setBusy(true);
    try {
      await countsService.record(openCount.id, selected.id, qty);
      await refreshCount();
      reset();
    } catch (error) {
      swalConfig.error(`Could not save the count: ${getErrorMessage(error)}`);
    } finally {
      setBusy(false);
    }
  };

  const handleApprove = async () => {
    if (!openCount) return;
    const changes = lines.filter(l => l.counted !== l.expected).length;
    const confirm = await swalConfig.confirm(
      `Approve ${openCount.countNo}?`,
      `${lines.length} items counted, ${changes} with a difference. Stock will be corrected.`,
      'Approve count'
    );
    if (!confirm.isConfirmed) return;
    setBusy(true);
    try {
      const changed = await countsService.approve(openCount.id);
      await queryClient.invalidateQueries({ queryKey: queryKeys.stockCounts });
      swalConfig.success(`Count approved: ${changed} stock corrections posted`);
    } catch (error) {
      swalConfig.error(`Could not approve: ${getErrorMessage(error)}`);
    } finally {
      setBusy(false);
    }
  };

  const handleCancel = async () => {
    if (!openCount) return;
    const confirm = await swalConfig.confirm(`Cancel ${openCount.countNo}?`, 'Counted quantities will be discarded. Stock is not changed.', 'Cancel count');
    if (!confirm.isConfirmed) return;
    try {
      await countsService.cancel(openCount.id);
      await queryClient.invalidateQueries({ queryKey: queryKeys.stockCounts });
    } catch (error) {
      swalConfig.error(`Could not cancel: ${getErrorMessage(error)}`);
    }
  };

  const fmt = (n: number) => (Number.isInteger(n) ? String(n) : n.toFixed(2));
  const isManager = state.currentUser?.role === 'admin' || state.currentUser?.role === 'manager';

  if (!openCount) {
    return (
      <div className="space-y-6">
        <div className="card p-6 flex flex-col md:flex-row md:items-center justify-between gap-4">
          <div>
            <h2 className="text-lg font-bold text-link">Stock count</h2>
            <p className="text-sm text-bodytext">
              Count what is on the shelves. You can count everything or just a few items; items you don't count are left as they are.
            </p>
          </div>
          {isManager && (
            <button type="button" onClick={handleStart} className="btn btn-primary btn-lg" disabled={busy}>
              <ClipboardCheck className="h-5 w-5" /><span>Start a count</span>
            </button>
          )}
        </div>
        <CountHistory counts={counts} />
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="card p-6 space-y-4">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-3">
          <div>
            <h2 className="text-lg font-bold text-link">Counting {openCount.countNo}</h2>
            <p className="text-sm text-bodytext">Started {openCount.createdAt.toLocaleString()} · {lines.length} items counted</p>
          </div>
          {isManager && (
            <div className="flex gap-2">
              <button type="button" onClick={handleCancel} className="btn btn-secondary btn-md" disabled={busy}>
                <XCircle className="h-4 w-4" /><span>Cancel count</span>
              </button>
              <button type="button" onClick={handleApprove} className="btn btn-primary btn-md" disabled={busy || lines.length === 0}>
                <ClipboardCheck className="h-4 w-4" /><span>Approve</span>
              </button>
            </div>
          )}
        </div>

        <form onSubmit={handleRecord} className="grid grid-cols-1 md:grid-cols-6 gap-3 items-start">
          <div className="relative md:col-span-3">
            <Input value={search} onChange={e => { setSearch(e.target.value); setSelected(null); }} onKeyDown={handleSearchKey}
                   className="input" placeholder="Scan a barcode or search an item" autoFocus />
            <ReportStatus loading={query.isFetching} error={query.error ?? saved.error} retry={() => { void query.refetch(); void saved.refetch(); }} />
            {matches.length > 0 && (
              <div className="absolute z-10 mt-1 w-full bg-card border border-border rounded-xl shadow-lg max-h-64 overflow-y-auto">
                {matches.map(p => (
                  <button key={p.id} type="button" onClick={() => choose(p)}
                          className="w-full text-left px-4 py-2 hover:bg-lightgray flex justify-between">
                    <span>{productLabel(p)}</span>
                    <span className="text-sm text-bodytext font-mono">{p.sku}</span>
                  </button>
                ))}
              </div>
            )}
          </div>
          <Input ref={countedRef} type="number" min="0" step="1" value={counted}
                 onChange={e => setCounted(e.target.value)} className="input"
                 placeholder="Counted" disabled={!selected} />
          <button type="submit" className="btn btn-primary btn-md" disabled={busy || !selected}>Save</button>
        </form>

        <div className="overflow-x-auto">
          <DataTable className="table">
            <thead className="table-header">
              <tr>
                <th className="table-header-cell">Item</th>
                <th className="table-header-cell text-right">System</th>
                <th className="table-header-cell text-right">Counted</th>
                <th className="table-header-cell text-right">Difference</th>
              </tr>
            </thead>
            <tbody className="bg-card divide-y divide-border">
              {lines.length === 0 && (
                <tr><td colSpan={4} className="table-cell text-center text-bodytext py-6">Nothing counted yet</td></tr>
              )}
              {[...lines].reverse().map(l => {
                const product = products.get(l.variantId);
                const diff = l.counted - l.expected;
                return (
                  <tr key={l.id}>
                    <td className="table-cell">
                      <div className="font-medium text-link">{product ? productLabel(product) : l.variantId}</div>
                      <div className="text-xs text-bodytext font-mono">
                        {product?.sku}
                      </div>
                    </td>
                    <td className="table-cell text-right">{fmt(l.expected)}</td>
                    <td className="table-cell text-right font-semibold">{fmt(l.counted)}</td>
                    <td className={`table-cell text-right font-semibold ${diff < 0 ? 'text-error' : diff > 0 ? 'text-success' : 'text-bodytext'}`}>
                      {diff > 0 ? '+' : ''}{fmt(diff)}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </DataTable>
        </div>
        <p className="text-xs text-bodytext">
          "System" is the quantity when the item was counted. Sales made afterwards are kept; only the difference is corrected.
          Counting an item again replaces its earlier count.
        </p>
      </div>
      <CountHistory counts={counts.filter(c => c.status !== 'open')} />
    </div>
  );
}

function CountHistory({ counts }: { counts: { id: string; countNo: string; status: string; createdAt: Date; closedAt?: Date }[] }) {
  if (counts.length === 0) return null;
  return (
    <div className="card p-6">
      <h3 className="font-semibold text-link mb-3">Previous counts</h3>
      <div className="divide-y divide-border">
        {counts.map(c => (
          <div key={c.id} className="py-2 flex justify-between text-sm">
            <span className="font-mono">{c.countNo}</span>
            <span className={`badge ${c.status === 'approved' ? 'badge-success' : 'badge-warning'}`}>{c.status}</span>
            <span className="text-bodytext">{(c.closedAt ?? c.createdAt).toLocaleDateString()}</span>
          </div>
        ))}
      </div>
    </div>
  );
}
