import {Input}from'@/components/ui/input';
import {DataTable}from'@/components/shared/DataTable';
import {ModalShell}from'@/components/shared/ModalShell';
import { useState, type FormEvent } from 'react';
import { useQuery } from '@tanstack/react-query';
import type { Customer } from '../../types';
import { useApp } from '../../context/SupabaseAppContext';
import { customersService, salesService } from '../../lib/services';
import { queryKeys } from '../../lib/queryClient';
import { getErrorMessage } from '../../lib/errors';
import { swalConfig } from '../../lib/sweetAlert';
import { ReportStatus } from '../reports/ReportStatus';
import { CollectPaymentModal } from './CollectPaymentModal';
import { CustomerStatement } from './CustomerStatement';

export function CustomerDetailModal({
  customer,
  onClose,
}: {
  customer: Customer;
  onClose: () => void;
}) {
  const { state } = useApp();
  const userId = state.currentUser!.id;
  const [tab, setTab] = useState<'details' | 'transactions'>('details');
  const [action, setAction] = useState<
    'collect' | 'statement' | 'adjust' | null
  >(null);
  const account = useQuery({
    queryKey: queryKeys.customerAccount(userId, customer.id),
    queryFn: () => customersService.getById(customer.id),
  });
  const current = account.data ?? customer;
  const sales = useQuery({
    queryKey: queryKeys.transactionList(
      userId,
      { customer: customer.id, q: current.phone || current.name },
      0,
    ),
    queryFn: () =>
      salesService.search({ q: current.phone || current.name }, 0, 50),
    enabled: tab === 'transactions',
  });
  const rows =
    sales.data?.filter((sale) => sale.customer_id === customer.id) ?? [];
  const money = (n: number) => `${state.settings.currency} ${n.toFixed(2)}`;
  const manager = ['admin', 'manager'].includes(state.currentUser!.role);
  return (
    <div
      className="modal-overlay"
      role="dialog"
      aria-modal="true"
      aria-label="Customer details"
    >
      <ModalShell className="modal max-w-4xl w-full">
        <div className="modal-header">
          <h2 className="text-xl font-bold">{current.name}</h2>
          <button
            type="button"
            onClick={onClose}
            className="btn btn-secondary btn-sm"
          >
            Close
          </button>
        </div>
        <div className="modal-body max-h-[75vh] overflow-y-auto space-y-5">
          <ReportStatus
            loading={account.isPending}
            error={account.error}
            retry={() => void account.refetch()}
          />
          <div className="card p-4 space-y-3">
            <p className="text-sm text-bodytext">Account balance</p>
            <p className="font-bold text-2xl">{money(current.creditUsed)}</p>
            <p>
              Credit limit: {money(current.creditLimit)} · Available:{' '}
              {money(current.creditLimit - current.creditUsed)}
            </p>
            <div className="flex flex-wrap gap-2">
              <button
                type="button"
                className="btn btn-primary btn-md"
                disabled={
                  !account.data || !!account.error || current.creditUsed <= 0
                }
                onClick={() => setAction('collect')}
              >
                Collect payment
              </button>
              <button
                type="button"
                className="btn btn-secondary btn-md"
                onClick={() => setAction('statement')}
              >
                Statement
              </button>
              {manager && (
                <button
                  type="button"
                  className="btn btn-secondary btn-md"
                  onClick={() => setAction('adjust')}
                >
                  Adjust balance
                </button>
              )}
            </div>
          </div>
          <nav className="flex gap-2" aria-label="Customer sections">
            <button
              type="button"
              className={`btn btn-md ${tab === 'details' ? 'btn-primary' : 'btn-secondary'}`}
              onClick={() => setTab('details')}
            >
              Customer details
            </button>
            <button
              type="button"
              className={`btn btn-md ${tab === 'transactions' ? 'btn-primary' : 'btn-secondary'}`}
              onClick={() => setTab('transactions')}
            >
              Transaction history
            </button>
          </nav>
          {tab === 'details' ? (
            <div className="space-y-2">
              <p>Phone: {current.phone}</p>
              <p>Email: {current.email || '—'}</p>
              <p>Address: {current.address || '—'}</p>
              <p>Price tier: {current.priceTier}</p>
              <p>Member since: {current.createdAt.toLocaleDateString()}</p>
            </div>
          ) : (
            <>
              <p className="text-sm text-bodytext">
                Latest 50 matching sales you can access
              </p>
              <ReportStatus
                loading={sales.isPending}
                error={sales.error}
                retry={() => void sales.refetch()}
              />
              {!sales.isPending && !sales.error && (
                <div className="overflow-x-auto">
                  <DataTable className="table">
                    <thead className="table-header">
                      <tr>
                        {['Invoice', 'Date', 'Status', 'Total', 'Cashier'].map(
                          (label) => (
                            <th key={label} className="table-cell text-left">
                              {label}
                            </th>
                          ),
                        )}
                      </tr>
                    </thead>
                    <tbody>
                      {rows.map((row) => (
                        <tr key={row.id}>
                          <td className="table-cell">{row.invoice_number}</td>
                          <td className="table-cell">
                            {new Date(row.created_at).toLocaleString('en-PK', {
                              timeZone: 'Asia/Karachi',
                            })}
                          </td>
                          <td className="table-cell">{row.status}</td>
                          <td className="table-cell whitespace-nowrap">
                            {money(row.total)}
                          </td>
                          <td className="table-cell">{row.cashier_name}</td>
                        </tr>
                      ))}
                    </tbody>
                  </DataTable>
                  {!rows.length && <p className="p-4">No sales found.</p>}
                </div>
              )}
            </>
          )}
        </div>
        {action === 'collect' && (
          <CollectPaymentModal
            customer={current}
            currency={state.settings.currency}
            onClose={() => setAction(null)}
          />
        )}
        {action === 'statement' && (
          <CustomerStatement
            customerId={current.id}
            onClose={() => setAction(null)}
          />
        )}
        {action === 'adjust' && manager && (
          <AdjustBalanceModal
            customer={current}
            onClose={() => setAction(null)}
          />
        )}
      </ModalShell>
    </div>
  );
}

function AdjustBalanceModal({
  customer,
  onClose,
}: {
  customer: Customer;
  onClose: () => void;
}) {
  const [requestId] = useState(() => crypto.randomUUID());
  const [amount, setAmount] = useState('');
  const [reason, setReason] = useState('');
  const [saving, setSaving] = useState(false);
  async function submit(event: FormEvent) {
    event.preventDefault();
    if (saving) return;
    setSaving(true);
    try {
      await customersService.adjust(
        customer.id,
        Number(amount),
        reason.trim(),
        requestId,
      );
      onClose();
    } catch (error) {
      swalConfig.error(getErrorMessage(error));
    } finally {
      setSaving(false);
    }
  }
  return (
    <div
      className="modal-overlay"
      role="dialog"
      aria-modal="true"
      aria-label="Adjust balance"
    >
      <form className="modal max-w-md w-full" onSubmit={submit}>
        <div className="modal-header">
          <h2 className="font-bold text-xl">
            Adjust balance · {customer.name}
          </h2>
        </div>
        <div className="modal-body space-y-4">
          <p>
            Use a negative amount for a write-off, or a positive amount to add
            debt.
          </p>
          <label className="block">
            Adjustment amount
            <Input
              className="input block"
              type="number"
              step="0.01"
              required
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
            />
          </label>
          <label className="block">
            Reason
            <textarea
              className="textarea block w-full"
              required
              value={reason}
              onChange={(e) => setReason(e.target.value)}
            />
          </label>
        </div>
        <div className="modal-footer">
          <button
            type="button"
            className="btn btn-secondary btn-md"
            disabled={saving}
            onClick={onClose}
          >
            Cancel
          </button>
          <button
            type="submit"
            className="btn btn-primary btn-md"
            disabled={
              saving ||
              !Number.isFinite(Number(amount)) ||
              Number(amount) === 0 ||
              !reason.trim()
            }
          >
            {saving ? 'Saving…' : 'Save adjustment'}
          </button>
        </div>
      </form>
    </div>
  );
}
