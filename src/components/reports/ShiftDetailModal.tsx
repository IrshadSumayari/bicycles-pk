import {DataTable}from'@/components/shared/DataTable';
import {ModalShell}from'@/components/shared/ModalShell';
import { useRef } from 'react';
import { useQuery } from '@tanstack/react-query';
import { shiftsService } from '../../lib/services';
import { queryKeys } from '../../lib/queryClient';
import { swalConfig } from '../../lib/sweetAlert';
import { ReportStatus } from './ReportStatus';

export function ShiftDetailModal({
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
  const query = useQuery({
    queryKey: queryKeys.shiftDetail(userId, id),
    queryFn: () => shiftsService.detail(id),
  });
  const slip = useRef<HTMLDivElement>(null);
  const money = (value: number | null) =>
    value == null ? '—' : `${currency} ${value.toFixed(2)}`;
  const time = (value: string | null) =>
    value
      ? new Date(value).toLocaleString('en-PK', { timeZone: 'Asia/Karachi' })
      : '—';
  function print() {
    if (!slip.current) return;
    const popup = window.open('', '_blank', 'width=900,height=700');
    if (!popup) {
      swalConfig.error('Allow pop-ups to print this shift');
      return;
    }
    popup.document.title = 'Cash shift summary';
    const style = popup.document.createElement('style');
    style.textContent =
      'body{font:14px sans-serif;padding:24px;color:#111}table{width:100%;border-collapse:collapse;margin:16px 0}th,td{text-align:left;padding:7px;border-bottom:1px solid #ddd}h2{font-size:22px}p{white-space:pre-wrap}';
    popup.document.head.appendChild(style);
    popup.document.body.appendChild(slip.current.cloneNode(true));
    popup.document.close();
    popup.focus();
    popup.setTimeout(() => {
      popup.print();
      popup.close();
    }, 250);
  }
  const summary = query.data?.summary;
  const session = summary?.session;
  const rows: [string, number | null][] =
    summary && session
      ? [
          ['Opening float', session.opening_float],
          ['Cash sales / deposits', summary.cash_sales],
          ['Refunds', summary.cash_refunds],
          ['Cash in', summary.cash_in],
          ['Cash out', summary.cash_out],
          ['Expected cash', session.expected_cash ?? summary.expected_cash],
          ['Counted cash', session.counted_cash],
          ['Difference', session.variance],
        ]
      : [];
  return (
    <div
      className="modal-overlay"
      role="dialog"
      aria-modal="true"
      aria-label="Shift detail"
    >
      <ModalShell className="modal max-w-4xl w-full">
        <div className="modal-header">
          <h2 className="text-lg font-bold">Shift detail</h2>
          <button
            type="button"
            className="btn btn-secondary btn-sm"
            onClick={onClose}
          >
            Close
          </button>
        </div>
        <div className="modal-body overflow-y-auto max-h-[70vh]">
          <ReportStatus
            loading={query.isPending}
            error={query.error}
            retry={() => void query.refetch()}
          />
          {query.data && summary && session && (
            <div ref={slip}>
              <h2 className="text-xl font-bold">
                {session.session_no} · {summary.user_name}
              </h2>
              <p>Status: {session.status}</p>
              <p>Opened: {time(session.opened_at)} (Asia/Karachi)</p>
              <p>
                Closed: {time(session.closed_at)} · By:{' '}
                {summary.closed_by_name ?? '—'}
              </p>
              <DataTable className="table">
                <tbody>
                  {rows.map(([label, value]) => (
                    <tr key={label}>
                      <th className="table-cell text-left">{label}</th>
                      <td className="table-cell">{money(value)}</td>
                    </tr>
                  ))}
                </tbody>
              </DataTable>
              {session.closing_notes && (
                <p className="whitespace-pre-wrap">
                  Notes: {session.closing_notes}
                </p>
              )}
              <h3 className="font-bold mt-4">Other payments</h3>
              <DataTable className="table">
                <tbody>
                  {Object.entries(summary.other_payments).map(
                    ([method, amount]) => (
                      <tr key={method}>
                        <td className="table-cell">{method}</td>
                        <td className="table-cell">{money(amount)}</td>
                      </tr>
                    ),
                  )}
                </tbody>
              </DataTable>
              <h3 className="font-bold mt-4">Cash movements</h3>
              <div className="overflow-x-auto">
                <DataTable className="table">
                  <thead className="table-header">
                    <tr>
                      {[
                        'Time',
                        'Type',
                        'Amount',
                        'Reason',
                        'Document',
                        'Who',
                      ].map((label) => (
                        <th className="table-cell" key={label}>
                          {label}
                        </th>
                      ))}
                    </tr>
                  </thead>
                  <tbody>
                    {query.data.movements.map((m) => (
                      <tr key={m.id}>
                        <td className="table-cell whitespace-nowrap">
                          {time(m.created_at)}
                        </td>
                        <td className="table-cell">{m.movement_type}</td>
                        <td className="table-cell whitespace-nowrap">
                          {money(m.amount)}
                        </td>
                        <td className="table-cell">{m.reason ?? '—'}</td>
                        <td className="table-cell">{m.document_no ?? '—'}</td>
                        <td className="table-cell">{m.user_name ?? '—'}</td>
                      </tr>
                    ))}
                  </tbody>
                </DataTable>
              </div>
              {!query.data.movements.length && <p>No cash movements.</p>}
            </div>
          )}
        </div>
        <div className="modal-footer">
          <button
            type="button"
            className="btn btn-primary btn-md"
            disabled={!query.data || !!query.error}
            onClick={print}
          >
            Print
          </button>
        </div>
      </ModalShell>
    </div>
  );
}
