import {DataTable}from'@/components/shared/DataTable';
import {ModalShell}from'@/components/shared/ModalShell';
import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { X } from 'lucide-react';
import { useApp } from '../../context/SupabaseAppContext';
import {
  salesService,
  saleFromDetail,
  productsService,
  customersService,
} from '../../lib/services';
import { queryKeys, invalidateTransactions } from '../../lib/queryClient';
import { getErrorMessage } from '../../lib/errors';
import { swalConfig } from '../../lib/sweetAlert';
import type { Sale } from '../../types';
import { ReturnModal } from '../pos/ReturnModal';
import { CheckoutModal } from '../pos/CheckoutModal';
import { ReceiptPrint } from '../pos/ReceiptPrint';

export function TransactionDetail({
  id,
  userId,
  currency,
  onClose,
}: {
  id: string;
  userId: string;
  currency: string;
  onClose: () => void;
}) {
  const { dispatch } = useApp();
  const [showReturn, setShowReturn] = useState(false);
  const [checkout, setCheckout] = useState(false);
  const [printSale, setPrintSale] = useState<Sale | null>(null);
  const [paid, setPaid] = useState(false);
  const [busy, setBusy] = useState(false);
  const [actionError, setActionError] = useState('');
  const query = useQuery({
    queryKey: queryKeys.transactionDetail(userId, id),
    queryFn: () => salesService.detail(id),
    staleTime: 0,
  });
  const detail = query.data;
  const money = (n: number | null) => `${currency} ${(n ?? 0).toFixed(2)}`;
  const date = (value: string) =>
    new Date(value).toLocaleString('en-GB', { timeZone: 'Asia/Karachi' });

  const removeDraft = async (close: boolean) => {
    setBusy(true);
    setActionError('');
    try {
      await salesService.delete(id);
      if (close) onClose();
    } catch (error) {
      setActionError(getErrorMessage(error));
    } finally {
      setBusy(false);
    }
  };
  const completeDraft = async () => {
    if (!detail) return;
    setBusy(true);
    setActionError('');
    try {
      const sale = saleFromDetail(detail);
      const [cart, customer] = await Promise.all([
        Promise.all(
          sale.items.map(async (item) => ({
            ...item,
            product: await productsService.getById(item.product.id),
          })),
        ),
        sale.customerId
          ? customersService.getById(sale.customerId)
          : Promise.resolve(null),
      ]);
      if (cart.some((item) => !item.product.active))
        throw new Error(
          'Some draft products are unavailable. Update the draft before completing it.',
        );
      dispatch({ type: 'CLEAR_CART' });
      cart.forEach((item) => dispatch({ type: 'ADD_TO_CART', payload: item }));
      if (customer)
        dispatch({ type: 'SET_SELECTED_CUSTOMER', payload: customer });
      setCheckout(true);
    } catch (error) {
      setActionError(getErrorMessage(error));
    } finally {
      setBusy(false);
    }
  };
  const paidDraft = (sale: Sale) => {
    // Preserve the successful receipt even if deleting the old draft fails.
    // Payment can never be offered again by this mounted detail after success.
    setPaid(true);
    setCheckout(false);
    setPrintSale(sale);
    void removeDraft(false);
  };
  return (
    <>
      <div className="modal-overlay">
        <ModalShell
          className="modal max-w-5xl"
          role="dialog"
          aria-modal="true"
          aria-labelledby="transaction-title"
        >
          <div className="modal-header">
            <h2 id="transaction-title" className="text-xl font-bold">
              Transaction details
            </h2>
            <button
              type="button"
              aria-label="Close transaction details"
              className="btn btn-secondary btn-sm"
              disabled={busy}
              onClick={onClose}
            >
              <X className="h-5 w-5" />
            </button>
          </div>
          <div className="modal-body space-y-5">
            {query.isPending && <p role="status">Loading transaction…</p>}
            {query.isError && (
              <div role="alert" className="space-y-2 text-error">
                <p>{getErrorMessage(query.error)}</p>
                <button
                  className="btn btn-secondary btn-md"
                  onClick={() => void query.refetch()}
                >
                  Try again
                </button>
              </div>
            )}
            {!query.isPending && !query.isError && !detail && (
              <p>
                {paid
                  ? 'Payment saved and draft removed.'
                  : 'This transaction is unavailable or you do not have access.'}
              </p>
            )}
            {actionError && (
              <p role="alert" className="text-error">
                {paid
                  ? 'Payment was saved. Only draft removal needs retrying. '
                  : ''}
                {actionError}
              </p>
            )}
            {paid && detail && (
              <p className="text-success">
                Payment saved. Do not collect payment again.
              </p>
            )}
            {detail && (
              <>
                <div className="grid sm:grid-cols-2 gap-3 text-sm">
                  <p>
                    <strong>Invoice:</strong> {detail.header.invoice_number}
                  </p>
                  <p>
                    <strong>Date:</strong> {date(detail.header.created_at!)}
                  </p>
                  <p>
                    <strong>Customer:</strong>{' '}
                    {detail.header.customer_name || 'Walk-in'}
                  </p>
                  <p>
                    <strong>Cashier:</strong>{' '}
                    {detail.header.cashier_name || '—'}
                  </p>
                  <p>
                    <strong>Status:</strong> {detail.header.status}
                  </p>
                  <p>
                    <strong>Total:</strong> {money(detail.header.total)}
                  </p>
                  <p>
                    <strong>Subtotal:</strong> {money(detail.header.subtotal)}
                  </p>
                  <p>
                    <strong>Discount:</strong>{' '}
                    {money(detail.header.discount_amount)}
                  </p>
                  <p>
                    <strong>Tax:</strong> {money(detail.header.tax_amount)}
                  </p>
                </div>
                {detail.header.notes && (
                  <p className="text-sm whitespace-pre-wrap">
                    {detail.header.notes}
                  </p>
                )}
                <section aria-label="Sale lines" className="overflow-x-auto">
                  <h3 className="font-semibold mb-2">Lines</h3>
                  <DataTable className="table">
                    <thead className="table-header">
                      <tr>
                        {[
                          'Item / SKU',
                          'Quantity',
                          'Returned',
                          'Unit price',
                          'Total',
                        ].map((label) => (
                          <th key={label} className="table-header-cell">
                            {label}
                          </th>
                        ))}
                      </tr>
                    </thead>
                    <tbody>
                      {detail.lines.map((line) => (
                        <tr key={line.id} className="table-row">
                          <td className="table-cell">
                            {line.description}
                            {line.is_gift ? ' (gift)' : ''}
                            <div className="text-xs text-bodytext">
                              {line.sku}
                            </div>
                          </td>
                          <td className="table-cell">
                            {line.quantity} {line.unit}
                          </td>
                          <td className="table-cell">
                            {line.returned_quantity}
                          </td>
                          <td className="table-cell">
                            {money(line.unit_price)}
                          </td>
                          <td className="table-cell">{money(line.total)}</td>
                        </tr>
                      ))}
                    </tbody>
                  </DataTable>
                </section>
                <section
                  aria-label="Payment history"
                  className="overflow-x-auto"
                >
                  <h3 className="font-semibold mb-2">Payments and refunds</h3>
                  <DataTable className="table">
                    <thead className="table-header">
                      <tr>
                        {[
                          'Date',
                          'Direction',
                          'Method',
                          'Amount',
                          'Cash received',
                          'Change',
                          'Reference',
                        ].map((label) => (
                          <th key={label} className="table-header-cell">
                            {label}
                          </th>
                        ))}
                      </tr>
                    </thead>
                    <tbody>
                      {detail.payments.map((payment) => (
                        <tr key={payment.id} className="table-row">
                          <td className="table-cell">
                            {date(payment.created_at!)}
                          </td>
                          <td className="table-cell">
                            {payment.direction === 'out'
                              ? 'Out / refund'
                              : 'In'}
                          </td>
                          <td className="table-cell">
                            {payment.method}
                            {payment.card_last4
                              ? ` · ****${payment.card_last4}`
                              : ''}
                          </td>
                          <td className="table-cell">
                            {money(payment.amount)}
                          </td>
                          <td className="table-cell">
                            {payment.tendered === null
                              ? '—'
                              : money(payment.tendered)}
                          </td>
                          <td className="table-cell">
                            {money(payment.change_given)}
                          </td>
                          <td className="table-cell">
                            {payment.reference || '—'}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </DataTable>
                  {detail.payments.length === 0 && (
                    <p className="text-sm text-bodytext p-3">
                      No payments recorded.
                    </p>
                  )}
                </section>
                <section aria-label="Returns" className="overflow-x-auto">
                  <h3 className="font-semibold mb-2">Returns</h3>
                  <DataTable className="table">
                    <thead className="table-header">
                      <tr>
                        {['Return', 'Date', 'Reason', 'Refund', 'Method'].map(
                          (label) => (
                            <th key={label} className="table-header-cell">
                              {label}
                            </th>
                          ),
                        )}
                      </tr>
                    </thead>
                    <tbody>
                      {detail.returns.map((ret) => (
                        <tr key={ret.id} className="table-row">
                          <td className="table-cell">{ret.return_no}</td>
                          <td className="table-cell">{date(ret.created_at)}</td>
                          <td className="table-cell">{ret.reason}</td>
                          <td className="table-cell">
                            {money(ret.refund_total)}
                          </td>
                          <td className="table-cell">{ret.refund_method}</td>
                        </tr>
                      ))}
                    </tbody>
                  </DataTable>
                  {detail.returns.length === 0 && (
                    <p className="text-sm text-bodytext p-3">
                      No returns recorded.
                    </p>
                  )}
                </section>
              </>
            )}
          </div>
          <div className="modal-footer flex-wrap">
            {detail && !query.isError && detail.header.status !== 'draft' && (
              <>
                <button
                  className="btn btn-secondary btn-md"
                  onClick={() => setPrintSale(saleFromDetail(detail))}
                >
                  Reprint receipt
                </button>
                {['completed', 'credit'].includes(
                  detail.header.status ?? '',
                ) && (
                  <button
                    className="btn btn-secondary btn-md"
                    onClick={() => setShowReturn(true)}
                  >
                    Return / exchange
                  </button>
                )}
              </>
            )}
            {detail?.header.status === 'draft' && !query.isError && (
              <>
                {!paid && (
                  <button
                    className="btn btn-primary btn-md"
                    disabled={busy}
                    onClick={completeDraft}
                  >
                    Complete draft
                  </button>
                )}
                <button
                  className="btn btn-secondary btn-md"
                  disabled={busy}
                  onClick={async () => {
                    if (
                      paid ||
                      (
                        await swalConfig.confirm(
                          'Delete draft?',
                          'This removes the unpaid draft.',
                          'Delete draft',
                        )
                      ).isConfirmed
                    )
                      await removeDraft(true);
                  }}
                >
                  {paid ? 'Retry draft removal' : 'Delete draft'}
                </button>
              </>
            )}
            <button
              className="btn btn-secondary btn-md"
              disabled={busy}
              onClick={onClose}
            >
              Close
            </button>
          </div>
        </ModalShell>
      </div>
      {detail && showReturn && (
        <ReturnModal
          isOpen
          onClose={() => {
            setShowReturn(false);
            invalidateTransactions();
          }}
          initialInvoice={detail.header.invoice_number}
        />
      )}
      {checkout && (
        <CheckoutModal
          isOpen
          onClose={() => setCheckout(false)}
          onComplete={paidDraft}
        />
      )}
      {printSale && (
        <ReceiptPrint
          sale={printSale}
          onClose={() => {
            setPrintSale(null);
            if (paid && !busy && !actionError) onClose();
          }}
        />
      )}
    </>
  );
}
