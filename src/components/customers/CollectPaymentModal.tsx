import {Input}from'@/components/ui/input';
import { useRef, useState, type FormEvent } from 'react';
import { useQuery } from '@tanstack/react-query';
import type { Customer } from '../../types';
import {
  customersService,
  shiftsService,
  type CustomerPaymentReceipt,
} from '../../lib/services';
import { queryKeys } from '../../lib/queryClient';
import { getErrorMessage } from '../../lib/errors';
import { swalConfig } from '../../lib/sweetAlert';
import { printAccountDocument } from '../../lib/customerCredit';
import { useApp } from '../../context/SupabaseAppContext';

export function CollectPaymentModal({
  customer,
  currency,
  onClose,
}: {
  customer: Customer;
  currency: string;
  onClose: () => void;
}) {
  const { state, dispatch } = useApp();
  const [requestId] = useState(() => crypto.randomUUID());
  const [amount, setAmount] = useState('');
  const [method, setMethod] = useState<'cash' | 'card' | 'digital'>('cash');
  const [tendered, setTendered] = useState('');
  const [reference, setReference] = useState('');
  const [last4, setLast4] = useState('');
  const [note, setNote] = useState('');
  const [saving, setSaving] = useState(false);
  const [receipt, setReceipt] = useState<CustomerPaymentReceipt | null>(null);
  const slip = useRef<HTMLDivElement>(null);
  const shift = useQuery({
    queryKey: queryKeys.cashShift,
    queryFn: shiftsService.current,
  });
  const money = (n: number) => `${currency} ${n.toFixed(2)}`;
  async function submit(event: FormEvent) {
    event.preventDefault();
    if (saving) return;
    setSaving(true);
    try {
      const result = await customersService.collect(
        customer.id,
        [
          {
            method,
            amount: Number(amount),
            tendered:
              method === 'cash' ? Number(tendered || amount) : undefined,
            reference: reference || undefined,
            cardLast4: method === 'card' ? last4 || undefined : undefined,
          },
        ],
        requestId,
        note,
      );
      setReceipt(result);
      // Refresh existing customer UI state from the server, never by subtracting locally.
      const updated = await customersService.getById(customer.id);
      if (state.selectedCustomer?.id === updated.id)
        dispatch({ type: 'SET_SELECTED_CUSTOMER', payload: updated });
    } catch (error) {
      swalConfig.error(getErrorMessage(error));
    } finally {
      setSaving(false);
    }
  }
  const cashBlocked = method === 'cash' && !shift.data;
  return (
    <div
      className="modal-overlay"
      role="dialog"
      aria-modal="true"
      aria-label="Collect payment"
    >
      <form className="modal max-w-lg w-full" onSubmit={submit}>
        <div className="modal-header">
          <h2 className="font-bold text-xl">
            {receipt ? 'Payment receipt' : 'Collect payment'}
          </h2>
        </div>
        <div className="modal-body max-h-[70vh] overflow-y-auto space-y-4">
          {receipt ? (
            <div ref={slip} className="space-y-3">
              <h2 className="font-bold text-xl">{receipt.payment_no}</h2>
              <p>Customer: {customer.name}</p>
              <p>Phone: {customer.phone}</p>
              <p>Paid: {money(receipt.paid)}</p>
              {receipt.payments.map((payment, index) => (
                <p key={index}>
                  Method: {payment.method} · {money(payment.amount)}
                  {payment.reference
                    ? ` · Reference: ${payment.reference}`
                    : ''}
                </p>
              ))}
              <p>New balance: {money(receipt.balance)}</p>
            </div>
          ) : (
            <>
              <p>
                {customer.name} · Balance {money(customer.creditUsed)}
              </p>
              <label className="block">
                Amount
                <Input
                  className="input block"
                  type="number"
                  required
                  min="0.01"
                  step="0.01"
                  max={customer.creditUsed}
                  value={amount}
                  onChange={(e) => setAmount(e.target.value)}
                />
              </label>
              <label className="block">
                Method
                <select
                  aria-label="Payment method"
                  className="select block"
                  value={method}
                  onChange={(e) => setMethod(e.target.value as typeof method)}
                >
                  <option value="cash">Cash</option>
                  <option value="card">Card</option>
                  <option value="digital">Digital</option>
                </select>
              </label>
              {method === 'cash' && (
                <label className="block">
                  Cash received
                  <Input
                    className="input block"
                    type="number"
                    step="0.01"
                    min={amount || '0'}
                    value={tendered}
                    placeholder={amount || 'Same as payment amount'}
                    onChange={(e) => setTendered(e.target.value)}
                  />
                </label>
              )}
              {method === 'card' && (
                <label className="block">
                  Card last four digits
                  <Input
                    className="input block"
                    inputMode="numeric"
                    pattern="[0-9]{4}"
                    maxLength={4}
                    value={last4}
                    onChange={(e) => setLast4(e.target.value)}
                  />
                </label>
              )}
              <label className="block">
                Reference
                <Input
                  className="input block"
                  maxLength={100}
                  value={reference}
                  onChange={(e) => setReference(e.target.value)}
                />
              </label>
              <label className="block">
                Note
                <textarea
                  className="textarea block w-full"
                  value={note}
                  onChange={(e) => setNote(e.target.value)}
                />
              </label>
              {cashBlocked && (
                <p className="text-warning">
                  Open your cash shift before collecting cash. Card and digital
                  payments are available.
                </p>
              )}
              {shift.error && (
                <p role="alert" className="text-error">
                  {getErrorMessage(shift.error)}
                </p>
              )}
            </>
          )}
        </div>
        <div className="modal-footer">
          <button
            type="button"
            className="btn btn-secondary btn-md"
            disabled={saving}
            onClick={onClose}
          >
            {receipt ? 'Done' : 'Cancel'}
          </button>
          {receipt ? (
            <button
              type="button"
              className="btn btn-primary btn-md"
              onClick={() => {
                try {
                  printAccountDocument(slip.current);
                } catch (error) {
                  swalConfig.error(getErrorMessage(error));
                }
              }}
            >
              Print receipt
            </button>
          ) : (
            <button
              type="submit"
              className="btn btn-primary btn-md"
              disabled={saving || cashBlocked || !amount}
            >
              {saving ? 'Collecting…' : 'Collect payment'}
            </button>
          )}
        </div>
      </form>
    </div>
  );
}
