import { useBusinessLookups } from '../../lib/lookups';
import { SalespersonSelect } from './SalespersonSelect';
import {Input}from'@/components/ui/input';
import {DataTable}from'@/components/shared/DataTable';
import {ModalShell}from'@/components/shared/ModalShell';
import { ReportStatus } from '../reports/ReportStatus';
import { useProductSearch } from '../../lib/hooks/useProducts';
import React, { useMemo, useState } from 'react';
import { X, Search, Undo2, Repeat, Trash2 } from 'lucide-react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { CartItem, Product, productLabel } from '../../types';
import { useApp } from '../../context/SupabaseAppContext';
import { useCashShift } from './CashShiftBar';
import { queryKeys } from '../../lib/queryClient';
import {
  returnsService, salesService,
  RefundMethod, ReturnLineInput, ReturnLookup,
} from '../../lib/services';
import { lineRefund, returnSelectionErrors, exchangeReadiness } from '../../lib/returns';
import { roundMoney } from '../../lib/pricing';
import { swalConfig } from '../../lib/sweetAlert';
import { getErrorMessage } from '../../lib/errors';

interface ReturnModalProps {
  isOpen: boolean;
  onClose: () => void;
  initialInvoice?: string;
}

type Condition = ReturnLineInput['condition'];
interface Selection { qty: string; condition: Condition | '' }
interface NewItem { key: string; product: Product; qty: string }

const REASONS = ['Other'];
const METHODS: { id: RefundMethod; label: string }[] = [
  { id: 'cash', label: 'Cash' }, { id: 'card', label: 'Card' }, { id: 'digital', label: 'Digital' }, { id: 'credit', label: 'Store credit' },
];

let itemCounter = 0;

// Return items from a receipt for a refund, or exchange them for other items.
export function ReturnModal({ isOpen, onClose, initialInvoice = '' }: ReturnModalProps) {
  const { state } = useApp();
  const businessLookups = useBusinessLookups(isOpen);
  const queryClient = useQueryClient();
  const { data: shift } = useCashShift();
  const [invoice, setInvoice] = useState(initialInvoice);
  const [lookup, setLookup] = useState<ReturnLookup | null>(null);
  const [finding, setFinding] = useState(false);
  const [selection, setSelection] = useState<Record<string, Selection>>({});
  const [reason, setReason] = useState(REASONS[0]);
  const [reasonNote, setReasonNote] = useState('');
  const [mode, setMode] = useState<'refund' | 'exchange'>('refund');
  const [method, setMethod] = useState<RefundMethod>('cash');
  const [cardLast4, setCardLast4] = useState('');
  const [reference, setReference] = useState('');
  const [newItems, setNewItems] = useState<NewItem[]>([]);
  const [salespersonId, setSalespersonId] = useState('');
  const [search, setSearch] = useState('');
  const [requestId, setRequestId] = useState(() => crypto.randomUUID());
  const [saving, setSaving] = useState(false);
  const [done, setDone] = useState<string | null>(null);

  const currency = state.settings.currency;
  const money = (n: number) => `${currency} ${n.toFixed(2)}`;

  const chosen = useMemo(() => (lookup?.lines ?? [])
    .map(line => ({ line, sel: selection[line.saleLineId] }))
    .filter(({ sel }) => sel && Number(sel.qty) > 0), [lookup, selection]);

  const credit = roundMoney(chosen.reduce((sum, { line, sel }) =>
    sum + lineRefund(line.total, line.quantity, line.returned, Number(sel!.qty)), 0));

  const exchangeCart: CartItem[] = useMemo(() => newItems
    .filter(i => Number(i.qty) > 0)
    .map(i => ({ product: i.product, quantity: Number(i.qty), discount: 0, discountType: 'fixed' as const, subtotal: 0 })),
  [newItems]);

  const { data: newQuote, error: quoteError, isFetching: quoteFetching } = useQuery({
    queryKey: queryKeys.exchangeQuote(exchangeCart, lookup?.sale.customerId),
    queryFn: () => salesService.quote({ cart: exchangeCart, customerId: lookup?.sale.customerId, payments: [] }),
    enabled: isOpen && mode === 'exchange' && exchangeCart.length > 0,
  });
  const quoteReady = !!newQuote && !quoteFetching && !quoteError;
  const newTotal = newQuote?.total ?? 0;
  const difference = roundMoney(newTotal - credit); // > 0: customer pays, < 0: refund

  const productQuery = useProductSearch({ q: search, limit: 20 }, isOpen && mode === 'exchange' && !!search.trim());
  const matches = search.trim() ? (productQuery.data?.rows ?? []).filter(p => p.kind !== 'service') : [];

  if (!isOpen) return null;

  const reset = () => {
    setLookup(null);
    setSelection({});
    setNewItems([]);
    setSalespersonId('');
    setMode('refund');
    setReasonNote('');
    setCardLast4('');
    setReference('');
    setRequestId(crypto.randomUUID());
    setDone(null);
  };

  const find = async (e?: React.FormEvent) => {
    e?.preventDefault();
    if (!invoice.trim()) return;
    setFinding(true);
    try {
      reset();
      setLookup(await returnsService.lookup(invoice.trim()));
    } catch (error) {
      swalConfig.error(getErrorMessage(error));
    } finally {
      setFinding(false);
    }
  };

  const select = (id: string, changes: Partial<Selection>) =>
    setSelection(prev => ({ ...prev, [id]: { ...(prev[id] ?? { qty: '0', condition: '' }), ...changes } }));

  const addItem = (product: Product) => {
    setNewItems(prev => [...prev, { key: `n${++itemCounter}`, product, qty: '1' }]);
    setSearch('');
  };

  // Money moving in this transaction, for the cash check
  const cashOut = mode === 'refund' ? (method === 'cash' ? credit : 0) : (difference < 0 && method === 'cash' ? -difference : 0);
  const cashIn = mode === 'exchange' && difference > 0 && method === 'cash';
  const needsShift = cashOut > 0 || cashIn;
  const needsCard = method === 'card' && ((mode === 'refund' && credit > 0) || (mode === 'exchange' && difference !== 0));
  const fullReason = reason === 'Other' ? reasonNote.trim() : reasonNote.trim() ? `${reason}: ${reasonNote.trim()}` : reason;

  const blockers: string[] = [];
  if (chosen.length === 0) blockers.push('Choose what is being returned');
  blockers.push(...returnSelectionErrors((lookup?.lines ?? []).map(line => ({
    ...line, qty: selection[line.saleLineId]?.qty ?? '', condition: selection[line.saleLineId]?.condition ?? '',
  }))));
  if (!fullReason) blockers.push('Give a reason');
  if (mode === 'exchange') blockers.push(...exchangeReadiness(newItems.map(item => ({
    description: productLabel(item.product), qty: item.qty, unit: 'piece',
  })), { available: !!newQuote, fetching: quoteFetching, error: !!quoteError }));
  if (needsShift && !shift) blockers.push('Open a cash shift to pay or refund cash');
  if (needsCard && !/^\d{4}$/.test(cardLast4)) blockers.push('Enter the last 4 card digits from the slip');
  if (method === 'credit' && !lookup?.sale.customerId) blockers.push('Store credit needs a sale with a customer');
  if (mode === 'exchange' && quoteError) blockers.push(getErrorMessage(quoteError));

  const submit = async () => {
    if (saving || !lookup || blockers.length > 0) return;
    const lines: ReturnLineInput[] = chosen.map(({ line, sel }) => ({
      saleLineId: line.saleLineId, quantity: Number(sel!.qty), condition: sel!.condition as Condition,
    }));
    setSaving(true);
    try {
      let message: string;
      if (mode === 'refund') {
        const r = await returnsService.refund({ requestId, saleId: lookup.sale.id, reason: fullReason, method, lines });
        message = `${r.returnNo}: refund ${money(r.refundTotal)} by ${METHODS.find(m => m.id === method)?.label}`;
      } else {
        const r = await returnsService.exchange({
          requestId, saleId: lookup.sale.id, reason: fullReason, returnLines: lines, newItems: exchangeCart,
          payments: difference > 0 ? [{ method, cardLast4: method === 'card' ? cardLast4 : undefined,
                                        reference: reference.trim() || undefined }] : [],
          refundMethod: method,
          salespersonId: salespersonId || undefined,
        });
        message = `${r.returnNo} → ${r.newInvoice}: ` + (r.customerPaid > 0
          ? `customer paid ${money(r.customerPaid)}`
          : r.refunded > 0 ? `refunded ${money(r.refunded)}` : 'no difference to pay');
      }
      setDone(message);
      queryClient.invalidateQueries({ queryKey: queryKeys.cashShift });
    } catch (error) {
      swalConfig.error(getErrorMessage(error));
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="modal-overlay">
      <ModalShell className="modal max-w-3xl">
        <div className="modal-header">
          <h2 className="text-xl font-bold text-link">Return / exchange</h2>
          <button onClick={onClose} className="text-bodytext hover:text-bodytext p-2 rounded-xl hover:bg-lightgray"><X className="h-6 w-6" /></button>
        </div>

        <div className="modal-body space-y-5">
          {done ? (
            <div className="bg-lightsuccess border border-lightsuccess rounded-xl p-6 text-center space-y-3">
              <p className="text-lg font-semibold text-success">Done</p>
              <p className="text-success">{done}</p>
              <button type="button" onClick={() => { reset(); setInvoice(''); }} className="btn btn-secondary btn-md">Another return</button>
            </div>
          ) : (
            <>
              <form onSubmit={find} className="flex gap-2">
                <Input value={invoice} onChange={e => setInvoice(e.target.value)} className="input" autoFocus
                       placeholder="Invoice number from the receipt, e.g. INV-001002" />
                <button type="submit" className="btn btn-primary btn-md" disabled={finding}>
                  <Search className="h-4 w-4" /><span>{finding ? 'Finding…' : 'Find'}</span>
                </button>
              </form>

              {lookup && (
                <>
                  <div className="text-sm text-link flex flex-wrap gap-x-6 gap-y-1">
                    <span className="font-semibold">{lookup.sale.invoiceNumber}</span>
                    <span>{lookup.sale.createdAt.toLocaleString()}</span>
                    <span>{money(lookup.sale.total)}</span>
                    {lookup.sale.customerName && <span>{lookup.sale.customerName}</span>}
                    {!lookup.withinWindow && (
                      <span className="text-warning">Older than {lookup.returnWindowDays} days: needs a manager</span>
                    )}
                  </div>
                  {lookup.previousReturns.length > 0 && (
                    <p className="text-xs text-bodytext">
                      Earlier returns: {lookup.previousReturns.map(r => `${r.returnNo} (${money(r.refundTotal)})`).join(', ')}
                    </p>
                  )}

                  <p className="text-sm text-bodytext">Inspect each returned item before choosing its condition. Only items confirmed suitable for resale go back into sellable stock. Apply the store’s approved return policy.</p>
                  <DataTable className="table">
                    <thead className="table-header">
                      <tr>
                        <th className="table-header-cell">Item</th>
                        <th className="table-header-cell text-right">Sold</th>
                        <th className="table-header-cell">Return</th>
                        <th className="table-header-cell">Condition</th>
                        <th className="table-header-cell text-right">Refund</th>
                      </tr>
                    </thead>
                    <tbody className="bg-card divide-y divide-border">
                      {lookup.lines.map(line => {
                        const left = line.quantity - line.returned;
                        const sel = selection[line.saleLineId];
                        const qty = Number(sel?.qty ?? 0);
                        return (
                          <tr key={line.saleLineId} className={left <= 0 ? 'opacity-50' : ''}>
                            <td className="table-cell">
                              <div className="font-medium">{line.description}</div>
                              <div className="text-xs text-bodytext">
                                {line.sku}
                                {line.returned > 0 ? ` · ${line.returned} already returned` : ''}
                              </div>
                            </td>
                            <td className="table-cell text-right">{line.quantity}</td>
                            <td className="table-cell">
                              <Input type="number" min="0" max={left} step="1" disabled={left <= 0}
                                     value={sel?.qty ?? ''} placeholder="0"
                                     onChange={e => select(line.saleLineId, { qty: e.target.value })} className="input w-20" />
                            </td>
                            <td className="table-cell">
                              <select aria-label={"Return condition for " + line.description} value={sel?.condition ?? ''} disabled={left <= 0}
                                      onChange={e => select(line.saleLineId, { condition: e.target.value as Condition })} className="select w-36">
                                <option value="" disabled>Inspect and choose</option>
                                <option value="resaleable">Inspected: back to stock</option>
                                <option value="damaged">Damaged: no restock</option>
                                <option value="faulty">Faulty: no restock</option>
                              </select>
                            </td>
                            <td className="table-cell text-right">
                              {qty > 0 ? money(lineRefund(line.total, line.quantity, line.returned, Math.min(qty, left))) : '-'}
                            </td>
                          </tr>
                        );
                      })}
                    </tbody>
                  </DataTable>

                  <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                    <select value={reason} onChange={e => setReason(e.target.value)} className="select">
                      {[...new Set([...(businessLookups.data?.return_reason || []), ...REASONS])].map(r => <option key={r}>{r}</option>)}
                    </select>
                    <Input value={reasonNote} onChange={e => setReasonNote(e.target.value)} className="input"
                           placeholder={reason === 'Other' ? 'Reason (required)' : 'Details (optional)'} />
                  </div>

                  <div className="flex gap-2">
                    <button type="button" onClick={() => setMode('refund')}
                            className={`btn btn-md ${mode === 'refund' ? 'btn-primary' : 'btn-secondary'}`}>
                      <Undo2 className="h-4 w-4" /><span>Refund</span>
                    </button>
                    <button type="button" onClick={() => setMode('exchange')}
                            className={`btn btn-md ${mode === 'exchange' ? 'btn-primary' : 'btn-secondary'}`}>
                      <Repeat className="h-4 w-4" /><span>Exchange</span>
                    </button>
                  </div>

                  {mode === 'exchange' && (
                    <div className="space-y-3 border border-border rounded-xl p-4">
                      <SalespersonSelect branch={newQuote?.branchId} value={salespersonId} onChange={setSalespersonId} disabled={saving} />
                      <div className="relative">
                        <Input value={search} onChange={e => setSearch(e.target.value)} className="input"
                               placeholder="Scan or search the replacement item (e.g. the right size)" />
                        <ReportStatus loading={productQuery.isFetching} error={productQuery.error} retry={() => void productQuery.refetch()} />
                        {matches.length > 0 && (
                          <div className="absolute z-10 mt-1 w-full bg-card border border-border rounded-xl shadow-lg">
                            {matches.map(p => (
                              <button key={p.id} type="button" onClick={() => addItem(p)}
                                      className="w-full text-left px-4 py-2 hover:bg-lightgray flex justify-between">
                                <span>{productLabel(p)}</span>
                                <span className="text-sm text-bodytext">{money(p.price)} · stock {p.stock}</span>
                              </button>
                            ))}
                          </div>
                        )}
                      </div>
                      {newItems.map(item => (
                        <div key={item.key} className="flex items-center gap-3">
                          <span className="flex-1">{productLabel(item.product)}</span>
                          <Input type="number" min="0" step="1" value={item.qty}
                                 onChange={e => setNewItems(prev => prev.map(x => x.key === item.key ? { ...x, qty: e.target.value } : x))}
                                 className="input w-24" placeholder="qty" />
                          <button type="button" onClick={() => setNewItems(prev => prev.filter(x => x.key !== item.key))}
                                  className="text-error p-1"><Trash2 className="h-4 w-4" /></button>
                        </div>
                      ))}
                    </div>
                  )}

                  <div className="bg-lightgray rounded-xl p-4 space-y-2 text-sm">
                    <div className="flex justify-between"><span>Value of returned items</span><span className="font-semibold">{money(credit)}</span></div>
                    {mode === 'exchange' && (
                      <>
                        <div className="flex justify-between"><span>Replacement items</span><span className="font-semibold">{quoteReady ? money(newTotal) : "Checking prices…"}</span></div>
                        <div className="flex justify-between text-base font-bold border-t pt-2">
                          <span>{!quoteReady ? 'Awaiting replacement quote' : difference > 0 ? 'Customer pays' : difference < 0 ? 'Refund to customer' : 'Even exchange'}</span>
                          <span>{quoteReady ? money(Math.abs(difference)) : '—'}</span>
                        </div>
                      </>
                    )}
                    {(mode === 'refund' ? credit > 0 : difference !== 0) && (
                      <div className="flex flex-wrap items-center gap-2 pt-2">
                        <span className="text-bodytext">{mode === 'exchange' && difference > 0 ? 'Paid by' : 'Refund by'}</span>
                        {METHODS.filter(m => m.id !== 'credit' || (mode === 'refund' || difference < 0)).map(m => (
                          <button key={m.id} type="button" onClick={() => setMethod(m.id)}
                                  className={`px-3 py-1.5 rounded-lg border text-sm ${method === m.id ? 'border-primary bg-lightprimary text-primary' : 'border-border'}`}>
                            {m.label}
                          </button>
                        ))}
                        {method === 'card' && (
                          <Input value={cardLast4} onChange={e => setCardLast4(e.target.value.replace(/\D/g, '').slice(0, 4))}
                                 className="input w-28" placeholder="Last 4" />
                        )}
                        {method === 'digital' && (
                          <Input value={reference} onChange={e => setReference(e.target.value)} className="input w-56" placeholder="Transaction ID" />
                        )}
                      </div>
                    )}
                  </div>

                  {blockers.length > 0 && chosen.length > 0 && (
                    <ul className="text-sm text-warning list-disc pl-5">{blockers.map(b => <li key={b}>{b}</li>)}</ul>
                  )}
                </>
              )}
            </>
          )}
        </div>

        <div className="modal-footer">
          <button type="button" onClick={onClose} className="btn btn-secondary btn-md">Close</button>
          {lookup && !done && (
            <button type="button" onClick={submit} className="btn btn-primary btn-md" disabled={saving || blockers.length > 0}>
              {saving ? 'Saving…' : mode === 'refund' ? `Refund ${money(credit)}` : 'Complete exchange'}
            </button>
          )}
        </div>
      </ModalShell>
    </div>
  );
}
