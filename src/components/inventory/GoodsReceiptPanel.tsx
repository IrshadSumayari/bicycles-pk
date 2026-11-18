import { ComboInput } from '@/components/shared/ComboInput';
import { useProductSearch } from '../../lib/hooks/useProducts';
import { ReportStatus } from '../reports/ReportStatus';
import { queryKeys } from '../../lib/queryClient';
import React, { useState } from 'react';
import { Trash2, PackagePlus, ChevronDown, ChevronRight } from 'lucide-react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { Product, productLabel } from '../../types';
import { useApp } from '../../context/SupabaseAppContext';
import { productsService, receiptsService, suppliersService } from '../../lib/services';
import { swalConfig } from '../../lib/sweetAlert';
import { getErrorMessage } from '../../lib/errors';
import { roundMoney } from '../../lib/pricing';

interface Line {
  key: string;
  product: Product;
  quantity: string;
  unitCost: string;
}

let lineCounter = 0;

// Receive a supplier delivery: every line is posted to stock in one transaction.
export function GoodsReceiptPanel() {
  const { state } = useApp();
  const queryClient = useQueryClient();
  const [supplierName, setSupplierName] = useState('');
  const [supplierReference, setSupplierReference] = useState('');
  const [notes, setNotes] = useState('');
  const [search, setSearch] = useState('');
  const [lines, setLines] = useState<Line[]>([]);
  const [requestId, setRequestId] = useState(() => crypto.randomUUID());
  const [posting, setPosting] = useState(false);
  const [expanded, setExpanded] = useState<string | null>(null);

  const { data: suppliers = [] } = useQuery({ queryKey: queryKeys.suppliers, queryFn: () => suppliersService.list() });
  const { data: receipts = [] } = useQuery({ queryKey: queryKeys.goodsReceipts, queryFn: () => receiptsService.list() });

  const query = useProductSearch({ q: search, limit: 20, withCosts: true }, !!search.trim());
  const matches = search.trim() ? (query.data?.rows ?? []).filter(p => p.trackInventory && p.kind !== 'service') : [];

  const addLine = (product: Product) => {
    setLines(prev => [...prev, {
      key: `line-${++lineCounter}`,
      product,
      quantity: '1',
      unitCost: product.cost ? String(product.cost) : '',
    }]);
    setSearch('');
  };

  const handleSearchKey = async (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key !== 'Enter') return;
    e.preventDefault();
    const term = search.trim().toLowerCase();
    let exact: Product | null = null;
    try { exact = await productsService.byCode(term); }
    catch (error) { swalConfig.error(getErrorMessage(error)); }
    if (exact && (!exact.trackInventory || exact.kind === 'service')) return;
    if (exact) addLine(exact);
    else if (!query.searching && !query.isPlaceholderData && matches.length === 1) addLine(matches[0]);
  };

  const updateLine = (key: string, changes: Partial<Line>) =>
    setLines(prev => prev.map(l => (l.key === key ? { ...l, ...changes } : l)));

  const total = roundMoney(lines.reduce((sum, l) => sum + (Number(l.quantity) || 0) * (Number(l.unitCost) || 0), 0));

  const handlePost = async () => {
    if (lines.length === 0) {
      swalConfig.error('Add at least one item');
      return;
    }
    for (const l of lines) {
      const qty = Number(l.quantity);
      if (!Number.isFinite(qty) || qty <= 0 || !Number.isInteger(qty)) {
        swalConfig.error(`Check the quantity for ${productLabel(l.product)}`);
        return;
      }
      if (l.unitCost === '' || !Number.isFinite(Number(l.unitCost)) || Number(l.unitCost) < 0) {
        swalConfig.error(`Enter the unit cost for ${productLabel(l.product)}`);
        return;
      }
    }

    const confirm = await swalConfig.confirm('Post this delivery?', `${lines.length} lines · ${state.settings.currency} ${total.toFixed(2)}. Stock and costs will be updated.`, 'Post delivery');
    if (!confirm.isConfirmed) return;

    setPosting(true);
    try {
      const receiptNo = await receiptsService.post({
        requestId,
        supplierName: supplierName.trim() || undefined,
        supplierReference: supplierReference.trim() || undefined,
        notes: notes.trim() || undefined,
        lines: lines.map(l => ({
          variantId: l.product.id,
          quantity: Number(l.quantity),
          unitCost: Number(l.unitCost),
        })),
      });
      setLines([]);
      setSupplierReference('');
      setNotes('');
      setRequestId(crypto.randomUUID());
      await queryClient.invalidateQueries({ queryKey: queryKeys.goodsReceipts });
      await queryClient.invalidateQueries({ queryKey: queryKeys.suppliers });
      swalConfig.success(`Delivery ${receiptNo} posted`);
    } catch (error) {
      swalConfig.error(`Could not post the delivery: ${getErrorMessage(error)}`);
    } finally {
      setPosting(false);
    }
  };

  const currency = state.settings.currency;

  return (
    <div className="space-y-6">
      <div className="card p-6 space-y-4">
        <h2 className="text-lg font-bold text-link">Receive goods</h2>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          <div className="block">
            <span className="block text-sm font-medium text-link mb-1">Supplier</span>
            <ComboInput aria-label="Supplier" value={supplierName} onChange={setSupplierName} className="input"
                        options={suppliers.map(s => s.name)} newLabel="supplier" placeholder="Choose or type a new supplier" />
          </div>
          <label className="block">
            <span className="block text-sm font-medium text-link mb-1">Supplier invoice / delivery note</span>
            <input value={supplierReference} onChange={e => setSupplierReference(e.target.value)} className="input" />
          </label>
          <label className="block">
            <span className="block text-sm font-medium text-link mb-1">Notes</span>
            <input value={notes} onChange={e => setNotes(e.target.value)} className="input" />
          </label>
        </div>

        <div className="relative">
          <input value={search} onChange={e => setSearch(e.target.value)} onKeyDown={handleSearchKey} className="input"
                 placeholder="Scan a barcode or search items to add" />
          <ReportStatus loading={query.isFetching} error={query.error} retry={() => void query.refetch()} />
          {matches.length > 0 && (
            <div className="absolute z-10 mt-1 w-full bg-card border border-border rounded-xl shadow-lg max-h-64 overflow-y-auto">
              {matches.map(p => (
                <button key={p.id} type="button" onClick={() => addLine(p)}
                        className="w-full text-left px-4 py-2 hover:bg-lightgray flex justify-between">
                  <span>{productLabel(p)}</span>
                  <span className="text-sm text-bodytext font-mono">{p.sku}</span>
                </button>
              ))}
            </div>
          )}
        </div>

        <div className="overflow-x-auto">
          <table className="table">
            <thead className="table-header">
              <tr>
                <th className="table-header-cell">Item</th>
                <th className="table-header-cell">Quantity</th>
                <th className="table-header-cell">Unit cost</th>
                <th className="table-header-cell text-right">Line total</th>
                <th className="table-header-cell" />
              </tr>
            </thead>
            <tbody className="bg-card divide-y divide-border">
              {lines.length === 0 && (
                <tr><td colSpan={5} className="table-cell text-center text-bodytext py-6">No items yet</td></tr>
              )}
              {lines.map(l => {
                const lineTotal = (Number(l.quantity) || 0) * (Number(l.unitCost) || 0);
                return (
                  <tr key={l.key}>
                    <td className="table-cell">
                      <div className="font-medium text-link">{productLabel(l.product)}</div>
                      <div className="text-xs text-bodytext font-mono">{l.product.sku}</div>
                    </td>
                    <td className="table-cell">
                      <div className="flex items-center gap-1">
                        <input type="number" min="0" step="1" value={l.quantity}
                               onChange={e => updateLine(l.key, { quantity: e.target.value })} className="input w-24" />
                        <span className="text-sm text-bodytext">{l.product.kind === 'pack' ? 'packs' : 'pcs'}</span>
                      </div>
                    </td>
                    <td className="table-cell">
                      <input type="number" min="0" step="0.01" value={l.unitCost}
                             onChange={e => updateLine(l.key, { unitCost: e.target.value })} className="input w-28" />
                    </td>
                    <td className="table-cell text-right font-medium">{currency} {lineTotal.toFixed(2)}</td>
                    <td className="table-cell">
                      <button type="button" onClick={() => setLines(prev => prev.filter(x => x.key !== l.key))}
                              className="text-error hover:text-error p-1">
                        <Trash2 className="h-4 w-4" />
                      </button>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>

        <div className="flex items-center justify-end gap-4">
          <span className="text-lg font-bold">Total {currency} {total.toFixed(2)}</span>
          <button type="button" onClick={handlePost} className="btn btn-primary btn-lg" disabled={posting || lines.length === 0}>
            <PackagePlus className="h-5 w-5" />
            <span>{posting ? 'Posting...' : 'Post delivery'}</span>
          </button>
        </div>
      </div>

      <div className="card p-6">
        <h3 className="font-semibold text-link mb-3">Recent deliveries</h3>
        {receipts.length === 0 && <p className="text-sm text-bodytext">No deliveries yet</p>}
        <div className="divide-y divide-border">
          {receipts.map(r => (
            <div key={r.id} className="py-2">
              <button type="button" onClick={() => setExpanded(expanded === r.id ? null : r.id)}
                      className="w-full flex items-center justify-between text-left">
                <span className="flex items-center gap-2">
                  {expanded === r.id ? <ChevronDown className="h-4 w-4" /> : <ChevronRight className="h-4 w-4" />}
                  <span className="font-mono">{r.receiptNo}</span>
                  <span className="text-link">{r.supplierName || 'No supplier'}</span>
                  {r.supplierReference && <span className="text-sm text-bodytext">({r.supplierReference})</span>}
                </span>
                <span className="text-sm text-bodytext">
                  {r.receivedAt.toLocaleDateString()} · {currency} {r.totalCost.toFixed(2)}
                </span>
              </button>
              {expanded === r.id && (
                <table className="mt-2 w-full text-sm">
                  <tbody>
                    {r.lines.map((l, i) => (
                      <tr key={i} className="text-link">
                        <td className="py-1 pl-6">{l.description}</td>
                        <td className="py-1 text-right">{l.quantity}</td>
                        <td className="py-1 text-right">× {l.unitCost.toFixed(2)}</td>
                        <td className="py-1 text-right">{currency} {l.lineCost.toFixed(2)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              )}
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
