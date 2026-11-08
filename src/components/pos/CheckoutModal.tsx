import { ComboInput } from '@/components/shared/ComboInput';
import { useBusinessLookups } from '../../lib/lookups';
import { SalespersonSelect } from './SalespersonSelect';
import {Input}from'@/components/ui/input';
import {ModalShell}from'@/components/shared/ModalShell';
import { connectionStore, isNetworkError } from '../../lib/connection';
import { cartFingerprint, pendingFor, readPendingCheckout, savePendingCheckout, clearPendingCheckout, type PendingCheckout } from '../../lib/pendingCheckout';
import { useState, useEffect, useMemo, useRef, useSyncExternalStore } from 'react';
import { keepPreviousData, useQuery, useQueryClient } from '@tanstack/react-query';
import { useCashShift } from './CashShiftBar';
import { queryKeys } from '../../lib/queryClient';
import { X, CreditCard, Banknote, Smartphone, Check, Receipt, Gift, Plus, Trash2, Ticket } from 'lucide-react';
import { describeOffer, discountCodesService } from '../../lib/discountCodes';
import { Sale, productLabel } from '../../types';
import { useApp } from '../../context/SupabaseAppContext';
import { ReceiptPrint } from './ReceiptPrint';
import { salesService, settingsService, PaymentInput } from '../../lib/services';
import { swalConfig } from '../../lib/sweetAlert';
import { getErrorMessage } from '../../lib/errors';
import { calculateTotals, roundMoney } from '../../lib/pricing';
import { allocateTenders, Tender, TenderMethod } from '../../lib/tenders';

interface CheckoutModalProps {
  isOpen: boolean;
  onClose: () => void;
  onComplete: (sale: Sale) => void;
}

const METHODS: { id: TenderMethod; label: string; icon: typeof Banknote }[] = [
  { id: 'cash', label: 'Cash', icon: Banknote },
  { id: 'card', label: 'Card', icon: CreditCard },
  { id: 'digital', label: 'Digital', icon: Smartphone },
  { id: 'credit', label: 'Store credit', icon: Receipt },
];

// Suggestions only: any bank name can be typed


let tenderCounter = 0;
const newTender = (method: TenderMethod): Tender => ({ key: `t${++tenderCounter}`, method, amount: '' });

export function CheckoutModal({ isOpen, onClose, onComplete }: CheckoutModalProps) {
  const { state, dispatch } = useApp();
  const bankLookup = useBusinessLookups(isOpen);
  const queryClient = useQueryClient();
  const { data: shift } = useCashShift();
  const [tenders, setTenders] = useState<Tender[]>([newTender('cash')]);
  const [isProcessing, setIsProcessing] = useState(false);
  const [showReceipt, setShowReceipt] = useState(false);
  const [completedSale, setCompletedSale] = useState<Sale | null>(null);
  const [notes, setNotes] = useState('');
  const [salespersonId, setSalespersonId] = useState('');
  // Automatic promotions removed from this sale, kept with their names for Undo
  const [skipped, setSkipped] = useState<{ id: string; name: string }[]>([]);
  const skippedPromotions = useMemo(() => skipped.map(s => s.id), [skipped]);
  const [codeInput, setCodeInput] = useState('');
  const [discountCode, setDiscountCode] = useState('');
  const candidate = useRef<PendingCheckout | null>(null);
  const connection = useSyncExternalStore(connectionStore.subscribe, connectionStore.getSnapshot, connectionStore.getServerSnapshot);

  // Reset when the dialog opens
  useEffect(() => {
    if (isOpen) {
      setTenders([newTender(shift ? 'cash' : 'card')]);
      setIsProcessing(false);
      setShowReceipt(false);
      setCompletedSale(null);
      setNotes('');
      setSalespersonId('');
      setSkipped([]);
      setCodeInput('');
      setDiscountCode('');
    }
    // Reset only when the dialog opens, not when the shift refreshes
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isOpen]);

  // Promotions can depend on the payment method, card type and bank
  const quotePayments = useMemo(
    () => tenders.map(t => ({ method: t.method, cardType: t.cardType, bankName: t.bankName })),
    [tenders]
  );

  // Totals come from the server so the screen always matches what is charged.
  const { data: quote, isFetching: quoting, error: quoteError } = useQuery({
    queryKey: queryKeys.quote(state.cart, state.selectedCustomer?.id, quotePayments, discountCode, skippedPromotions),
    queryFn: () => salesService.quote({ cart: state.cart, customerId: state.selectedCustomer?.id, payments: quotePayments, discountCode, skippedPromotions }),
    // Keep showing the last totals while a removal is re-priced
    placeholderData: keepPreviousData,
    enabled: isOpen && state.cart.length > 0,
    staleTime: 0,
  });

  // The selected customer's usable codes, offered with one tap
  const { data: customerCodes = [] } = useQuery({
    queryKey: queryKeys.customerDiscountCodes(state.selectedCustomer?.id ?? ''),
    queryFn: () => discountCodesService.forCustomer(state.selectedCustomer!.id),
    enabled: isOpen && !!state.selectedCustomer,
  });
  const readyCodes = customerCodes.filter(c => c.status === 'ready' && c.code !== discountCode);

  const local = calculateTotals(state.cart, state.settings.taxRate);
  const totalDiscount = quote?.discountAmount ?? local.totalDiscount;
  const taxAmount = quote?.taxAmount ?? local.taxAmount;
  const total = quote?.total ?? local.total;
  const appliedDiscounts = quote?.appliedDiscounts ?? [];
  const freeGifts = quote?.gifts ?? [];
  const currency = state.settings.currency;
  const money = (n: number) => `${currency} ${n.toFixed(2)}`;

  const creditAvailable = state.selectedCustomer
    ? state.selectedCustomer.creditLimit - state.selectedCustomer.creditUsed
    : 0;
  const allocation = allocateTenders(tenders, total, { hasShift: !!shift, hasCustomer: !!state.selectedCustomer, creditAvailable });

  const payments: PaymentInput[] = allocation.lines.map(({ tender, amount }) => ({
    method: tender.method, amount,
    tendered: tender.method === 'cash' && tender.received ? Number(tender.received) : undefined,
    reference: tender.reference?.trim() || undefined,
    cardType: tender.method === 'card' ? tender.cardType : undefined,
    cardLast4: tender.method === 'card' ? tender.cardLast4 : undefined,
    bankName: tender.method === 'card' ? tender.bankName?.trim() || undefined : undefined,
    holderName: tender.method === 'card' ? tender.holderName?.trim() || undefined : undefined,
  }));
  const fingerprint = cartFingerprint(state.cart, state.selectedCustomer?.id, payments, salespersonId, discountCode, skippedPromotions);
  useEffect(() => {
    if (!isOpen) return;
    let previous: PendingCheckout | null = null;
    try { previous = readPendingCheckout(sessionStorage); } catch { /* Saving will refuse an unsafe post. */ }
    candidate.current = pendingFor(previous, fingerprint, Date.now(), () => crypto.randomUUID());
  }, [isOpen, fingerprint]);
  useEffect(() => {
    if (!state.cart.length) {
      try { clearPendingCheckout(sessionStorage); } catch { /* Empty carts never post a sale. */ }
    }
  }, [state.cart.length]);

  const update = (key: string, changes: Partial<Tender>) =>
    setTenders(prev => prev.map(t => (t.key === key ? { ...t, ...changes } : t)));

  // Adding a payment fixes the current lines at their amounts; the new line takes what is left
  const addTender = () => {
    const used = new Set(tenders.map(t => t.method));
    const next = METHODS.find(m => !used.has(m.id) && (m.id !== 'cash' || shift))?.id ?? 'card';
    setTenders(prev => [
      ...prev.map((t, i) => ({ ...t, amount: t.amount === '' ? String(allocation.lines[i]?.amount ?? 0) : t.amount })),
      newTender(next),
    ]);
  };

  if (!isOpen && !showReceipt) return null;

  const canPay = connection.status !== 'offline' && !isProcessing && !quoting && !!quote && !quoteError && allocation.ok;

  const handlePayment = async () => {
    if (!canPay) return;
    setIsProcessing(true);
    try {
      const now = Date.now();
      const record = pendingFor(readPendingCheckout(sessionStorage), fingerprint, now, () =>
        pendingFor(candidate.current, fingerprint, now, () => crypto.randomUUID()).requestId);
      // Persist before sending: a lost response must not turn a retry into another sale.
      savePendingCheckout(sessionStorage, record);
      candidate.current = record;

      // One database transaction: prices, promotions, tax, stock, store credit,
      // payments and the sale. A retry with the same request id is safe.
      const savedSale = await salesService.post({
        requestId: record.requestId,
        cart: state.cart,
        customerId: state.selectedCustomer?.id,
        payments,
        notes: notes.trim() || undefined,
        salespersonId: salespersonId || undefined,
        discountCode: discountCode || undefined,
        skippedPromotions,
      });
      if (discountCode) void queryClient.invalidateQueries({ queryKey: queryKeys.discountCodes });
      clearPendingCheckout(sessionStorage);
      queryClient.invalidateQueries({ queryKey: queryKeys.cashShift });

      // Refresh settings; post() invalidates customer and product queries.
      try {
        const settings = await settingsService.get();
        dispatch({ type: 'SET_SETTINGS', payload: settings });
      } catch (error) {
        console.error('Error refreshing data after sale:', error);
      }

      dispatch({ type: 'CLEAR_CART' });
      setCompletedSale(savedSale);
      onComplete(savedSale);
      setIsProcessing(false);
      setShowReceipt(true);
    } catch (error) {
      console.error('Payment processing error:', error);
      setIsProcessing(false);
      swalConfig.error(isNetworkError(error)
        ? 'We could not confirm this sale. Check the Transactions screen before taking payment again.'
        : `Payment failed: ${getErrorMessage(error)}`);
    }
  };

  const handleCloseModal = () => {
    setShowReceipt(false);
    setCompletedSale(null);
    onClose();
  };

  const isTouchMode = state.settings.interfaceMode === 'touch';

  return (
    <>
      {!showReceipt && isOpen && (
        <div className="modal-overlay">
          <ModalShell className={`modal ${isTouchMode ? 'max-w-xl' : 'max-w-lg'}`}>
            <div className="modal-header">
              <h2 className={`font-bold text-link ${isTouchMode ? 'text-xl' : 'text-lg'}`}>Complete Payment</h2>
              <button onClick={onClose} disabled={isProcessing}
                      className="text-bodytext hover:text-bodytext p-2 rounded-xl hover:bg-lightgray transition-colors disabled:opacity-50">
                <X className="h-6 w-6" />
              </button>
            </div>

            <div className="modal-body space-y-6">
              {connection.status === 'offline' && <p role="alert" className="bg-lighterror border border-lighterror rounded-xl p-4 text-sm text-error">Offline — use the paper sales book</p>}
              {quoteError && (
                <div className="bg-lighterror border border-lighterror rounded-xl p-4 text-sm text-error">{getErrorMessage(quoteError)}</div>
              )}

              {(appliedDiscounts.length > 0 || skipped.length > 0) && (
                <div className="bg-lightsuccess border border-lightsuccess rounded-xl p-4">
                  <div className="flex items-start space-x-3">
                    <Gift className="h-5 w-5 text-success flex-shrink-0 mt-0.5" />
                    <div className="flex-1 min-w-0 space-y-1">
                      <h4 className="font-semibold text-success">Discounts applied</h4>
                      {appliedDiscounts.map((discount) => (
                        <div key={discount.discountId} className="flex items-center gap-2 text-sm text-success">
                          <span className="font-medium truncate">{discount.discountName}</span>
                          {discount.type !== 'free_gift' && <span className="whitespace-nowrap">- {money(discount.discountAmount)}</span>}
                          {/* Removing takes the discount off this sale; the total is re-priced */}
                          <button type="button" disabled={isProcessing || quoting}
                                  onClick={() => discount.type === 'code'
                                    ? setDiscountCode('')
                                    : setSkipped(prev => [...prev, { id: discount.discountId, name: discount.discountName }])}
                                  aria-label={`Remove ${discount.discountName} from this sale`} title="Remove from this sale"
                                  className="ml-auto flex-shrink-0 rounded-lg p-1.5 text-success hover:bg-lightsuccess disabled:opacity-50">
                            <X className="h-4 w-4" />
                          </button>
                        </div>
                      ))}
                      {appliedDiscounts.length === 0 && <p className="text-sm text-success">No discounts on this sale.</p>}
                      {freeGifts.length > 0 && (
                        <div className="text-sm text-success">
                          <span className="font-medium">Free gifts: </span>{freeGifts.map(g => g.description).join(', ')}
                        </div>
                      )}
                      {skipped.map(s => (
                        <div key={s.id} className="flex items-center gap-2 text-sm text-bodytext">
                          <span className="truncate line-through">{s.name}</span>
                          <span className="whitespace-nowrap">removed</span>
                          <button type="button" disabled={isProcessing || quoting}
                                  onClick={() => setSkipped(prev => prev.filter(p => p.id !== s.id))}
                                  className="ml-auto flex-shrink-0 text-primary font-medium disabled:opacity-50">
                            Undo
                          </button>
                        </div>
                      ))}
                    </div>
                  </div>
                </div>
              )}

              {/* Discount code: the server checks it and adds it to the discounts */}
              <div className="space-y-2">
                {discountCode ? (
                  <div className="flex items-center justify-between border border-border rounded-xl px-3 py-2 text-sm">
                    <span className="flex items-center gap-2"><Ticket className="h-4 w-4" />Code <span className="font-mono font-semibold">{discountCode}</span></span>
                    <button type="button" onClick={() => setDiscountCode('')} disabled={isProcessing} className="text-error text-sm">Remove</button>
                  </div>
                ) : (
                  <form className="flex gap-2" onSubmit={e => { e.preventDefault(); setDiscountCode(codeInput.replace(/\s/g, '').toUpperCase()); }}>
                    <Input value={codeInput} onChange={e => setCodeInput(e.target.value)} placeholder="Discount code"
                           aria-label="Discount code" className="input font-mono uppercase" disabled={isProcessing} autoComplete="off" />
                    <button type="submit" className="btn btn-secondary btn-md" disabled={isProcessing || !codeInput.trim()}>Apply</button>
                  </form>
                )}
                {readyCodes.length > 0 && (
                  <div className="flex flex-wrap items-center gap-2 text-sm">
                    <span className="text-bodytext">{state.selectedCustomer?.name}'s codes:</span>
                    {readyCodes.map(c => (
                      <button key={c.id} type="button" disabled={isProcessing} onClick={() => setDiscountCode(c.code)}
                              className="badge badge-success cursor-pointer hover:opacity-80">
                        {c.code} · {describeOffer(c, currency)}
                      </button>
                    ))}
                  </div>
                )}
              </div>

              <SalespersonSelect branch={quote?.branchId} value={salespersonId} onChange={setSalespersonId} disabled={isProcessing} />

              {/* Order summary */}
              <div>
                <div className="space-y-2 mb-4 max-h-32 overflow-y-auto">
                  {state.cart.map((item, index) => (
                    <div key={index} className="flex justify-between text-sm">
                      <span className="truncate flex-1 mr-2">
                        {productLabel(item.product)} × {item.quantity}
                      </span>
                      <span className="font-medium">{money(item.subtotal)}</span>
                    </div>
                  ))}
                  {freeGifts.map((gift, index) => (
                    <div key={`gift-${index}`} className="flex justify-between text-sm text-success">
                      <span className="truncate flex-1 mr-2">🎁 {gift.description} × {gift.quantity}</span>
                      <span className="font-medium">{money(0)}</span>
                    </div>
                  ))}
                </div>
                <div className="space-y-1 pt-3 border-t border-border text-sm">
                  <div className="flex justify-between"><span>Subtotal</span><span>{money(quote?.subtotal ?? local.subtotal)}</span></div>
                  {totalDiscount > 0 && (
                    <div className="flex justify-between text-success"><span>Discount</span><span>-{money(totalDiscount)}</span></div>
                  )}
                  <div className="flex justify-between"><span>Tax ({quote?.taxRate ?? state.settings.taxRate}%)</span><span>{money(taxAmount)}</span></div>
                  <div className="flex justify-between text-lg font-bold pt-2 border-t border-border">
                    <span>Total</span><span>{money(total)}</span>
                  </div>
                </div>
              </div>

              {/* Payments */}
              <div className="space-y-3">
                <h3 className="font-semibold text-link">Payment</h3>
                {tenders.map((tender, index) => {
                  const line = allocation.lines[index];
                  const error = allocation.errors[index];
                  return (
                    <div key={tender.key} className="border border-border rounded-xl p-3 space-y-3">
                      <div className="flex flex-wrap items-center gap-2">
                        {METHODS.map(({ id, label, icon: Icon }) => {
                          const disabled = (id === 'cash' && !shift) || (id === 'credit' && !state.selectedCustomer);
                          return (
                            <button key={id} type="button" disabled={disabled || isProcessing}
                                    title={id === 'cash' && !shift ? 'Open a cash shift first' : id === 'credit' && !state.selectedCustomer ? 'Select a customer first' : undefined}
                                    onClick={() => update(tender.key, { method: id })}
                                    className={`flex items-center gap-1 px-3 py-2 rounded-lg border text-sm ${
                                      tender.method === id ? 'border-primary bg-lightprimary text-primary' : 'border-border'
                                    } ${disabled ? 'opacity-40 cursor-not-allowed' : ''}`}>
                              <Icon className="h-4 w-4" /><span>{label}</span>
                            </button>
                          );
                        })}
                        {tenders.length > 1 && (
                          <button type="button" onClick={() => setTenders(prev => prev.filter(t => t.key !== tender.key))}
                                  className="ml-auto text-error hover:text-error p-1" title="Remove payment">
                            <Trash2 className="h-4 w-4" />
                          </button>
                        )}
                      </div>

                      <div className="grid grid-cols-2 gap-3">
                        <label className="block">
                          <span className="block text-xs font-medium text-bodytext mb-1">Amount</span>
                          <Input type="number" min="0" step="0.01" value={tender.amount}
                                 onChange={e => update(tender.key, { amount: e.target.value })}
                                 placeholder={line ? line.amount.toFixed(2) : ''} className="input" disabled={isProcessing} />
                        </label>

                        {tender.method === 'cash' && (
                          <label className="block">
                            <span className="block text-xs font-medium text-bodytext mb-1">Cash received</span>
                            <Input type="number" min="0" step="0.01" value={tender.received ?? ''}
                                   onChange={e => update(tender.key, { received: e.target.value })}
                                   placeholder={line ? line.amount.toFixed(2) : ''} className="input" disabled={isProcessing} />
                          </label>
                        )}
                        {tender.method === 'digital' && (
                          <label className="block">
                            <span className="block text-xs font-medium text-bodytext mb-1">Transaction ID</span>
                            <Input value={tender.reference ?? ''} onChange={e => update(tender.key, { reference: e.target.value })}
                                   placeholder="JazzCash / Easypaisa / bank transfer ref" className="input" disabled={isProcessing} />
                          </label>
                        )}
                        {tender.method === 'credit' && state.selectedCustomer && (
                          <div className="text-sm text-bodytext self-end pb-2">Available: {money(creditAvailable)}</div>
                        )}
                      </div>

                      {tender.method === 'card' && (
                        // Charged on the bank terminal; never type or store the full card number here
                        <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
                          <select value={tender.cardType ?? ''} onChange={e => update(tender.key, { cardType: e.target.value })}
                                  className="select" disabled={isProcessing}>
                            <option value="">Card type</option>
                            <option value="visa">Visa</option>
                            <option value="mastercard">Mastercard</option>
                            <option value="unionpay">UnionPay</option>
                            <option value="amex">Amex</option>
                            <option value="other">Other</option>
                          </select>
                          <Input inputMode="numeric" autoComplete="off" maxLength={4} value={tender.cardLast4 ?? ''}
                                 onChange={e => update(tender.key, { cardLast4: e.target.value.replace(/\D/g, '').slice(0, 4) })}
                                 placeholder="Last 4" className="input" disabled={isProcessing} />
                          <ComboInput aria-label="Bank" value={tender.bankName ?? ''} onChange={bankName => update(tender.key, { bankName })}
                                      options={bankLookup.data?.bank || []} placeholder="Bank (optional)" className="input" disabled={isProcessing} />
                          <Input value={tender.reference ?? ''} onChange={e => update(tender.key, { reference: e.target.value })}
                                 placeholder="Terminal slip no. (optional)" className="input" disabled={isProcessing} />
                        </div>
                      )}

                      {line && line.change > 0 && (
                        <p className="text-sm font-semibold text-success">Change: {money(line.change)}</p>
                      )}
                      {error && <p className="text-sm text-error">{error}</p>}
                    </div>
                  );
                })}

                <div className="flex items-center justify-between">
                  <button type="button" onClick={addTender} className="btn btn-secondary btn-sm" disabled={isProcessing || allocation.remaining <= 0}>
                    <Plus className="h-4 w-4" /><span>Split payment</span>
                  </button>
                  <span className={`text-sm font-semibold ${allocation.remaining === 0 ? 'text-success' : 'text-error'}`}>
                    {allocation.remaining === 0
                      ? 'Fully paid'
                      : allocation.remaining > 0 ? `Still to pay: ${money(allocation.remaining)}` : `Over by ${money(-allocation.remaining)}`}
                  </span>
                </div>
              </div>

              <label className="block">
                <span className="block text-xs font-medium text-bodytext mb-1">Notes (optional)</span>
                <Input value={notes} onChange={e => setNotes(e.target.value)} className="input" disabled={isProcessing} />
              </label>
            </div>

            <div className="modal-footer">
              <button onClick={onClose} disabled={isProcessing} className="btn btn-secondary btn-md px-6 py-3">Cancel</button>
              <button onClick={handlePayment} disabled={!canPay}
                      className="btn btn-success btn-md flex items-center space-x-2 min-w-[160px] justify-center px-6 py-3">
                {isProcessing ? (
                  <>
                    <div className="animate-spin rounded-full h-4 w-4 border-b-2 border-white"></div>
                    <span>Processing...</span>
                  </>
                ) : (
                  <>
                    <Check className="h-4 w-4" />
                    <span>Complete {money(roundMoney(total))}</span>
                  </>
                )}
              </button>
            </div>
          </ModalShell>
        </div>
      )}

      {showReceipt && completedSale && <ReceiptPrint sale={completedSale} onClose={handleCloseModal} />}
    </>
  );
}
