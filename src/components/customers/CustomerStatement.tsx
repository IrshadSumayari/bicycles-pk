import {Input}from'@/components/ui/input';
import {DataTable}from'@/components/shared/DataTable';
import {ModalShell}from'@/components/shared/ModalShell';
import { useRef, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { useApp } from '../../context/SupabaseAppContext';
import { customersService } from '../../lib/services';
import { queryKeys } from '../../lib/queryClient';
import { rangeFor, type ReportPreset } from '../../lib/reportDates';
import {
  customerStatementLink,
  printAccountDocument,
} from '../../lib/customerCredit';
import { getErrorMessage } from '../../lib/errors';
import { swalConfig } from '../../lib/sweetAlert';
import { ReportStatus } from '../reports/ReportStatus';

export function CustomerStatement({
  customerId,
  onClose,
}: {
  customerId: string;
  onClose: () => void;
}) {
  const { state } = useApp();
  const [preset, setPreset] = useState<ReportPreset>('this_month');
  const [range, setRange] = useState(() => rangeFor('this_month', new Date()));
  const valid = !!range.from && !!range.to && range.from <= range.to;
  const slip = useRef<HTMLDivElement>(null);
  const query = useQuery({
    queryKey: queryKeys.customerStatement(
      state.currentUser!.id,
      customerId,
      range.from,
      range.to,
    ),
    queryFn: () => customersService.statement(customerId, range.from, range.to),
    enabled: valid,
  });
  const data = query.data;
  const money = (n: number) => `${state.settings.currency} ${n.toFixed(2)}`;
  const link = data
    ? customerStatementLink(
        data.customer.phone,
        data.customer.name,
        state.settings.storeName,
        range.from,
        range.to,
        data.closing_balance,
        state.settings.currency,
      )
    : null;
  return (
    <div
      className="modal-overlay"
      role="dialog"
      aria-modal="true"
      aria-label="Customer statement"
    >
      <ModalShell className="modal max-w-5xl w-full">
        <div className="modal-header">
          <h2 className="font-bold text-xl">Statement</h2>
          <button
            className="btn btn-secondary btn-sm"
            type="button"
            onClick={onClose}
          >
            Close
          </button>
        </div>
        <div className="modal-body max-h-[70vh] overflow-y-auto space-y-4">
          <div className="flex flex-wrap items-end gap-3">
            <label>
              Period
              <select
                aria-label="Statement period"
                className="select block"
                value={preset}
                onChange={(e) => {
                  const next = e.target.value as ReportPreset;
                  setPreset(next);
                  if (next !== 'custom') setRange(rangeFor(next, new Date()));
                }}
              >
                <option value="today">Today</option>
                <option value="yesterday">Yesterday</option>
                <option value="this_week">This week</option>
                <option value="this_month">This month</option>
                <option value="last_month">Last month</option>
                <option value="custom">Custom</option>
              </select>
            </label>
            <label>
              From
              <Input
                className="input block"
                type="date"
                value={range.from}
                max={range.to}
                onChange={(e) => {
                  setPreset('custom');
                  setRange({ ...range, from: e.target.value });
                }}
              />
            </label>
            <label>
              To
              <Input
                className="input block"
                type="date"
                value={range.to}
                min={range.from}
                onChange={(e) => {
                  setPreset('custom');
                  setRange({ ...range, to: e.target.value });
                }}
              />
            </label>
          </div>
          {!valid ? (
            <p role="alert">Choose both dates with From on or before To.</p>
          ) : (
            <ReportStatus
              loading={query.isPending}
              error={query.error}
              retry={() => void query.refetch()}
            />
          )}
          {valid && data && !query.error && (
            <div ref={slip} className="space-y-3">
              <h2 className="font-bold text-xl">
                {state.settings.storeName} · Customer statement
              </h2>
              <p>
                {data.customer.name} · {data.customer.phone}
              </p>
              <p>
                {range.from} to {range.to} · Asia/Karachi
              </p>
              <p>Opening balance: {money(data.opening_balance)}</p>
              <div className="overflow-x-auto">
                <DataTable className="table">
                  <thead className="table-header">
                    <tr>
                      {[
                        'Date',
                        'Type / note',
                        'Document',
                        'Debit',
                        'Credit',
                        'Balance',
                      ].map((label) => (
                        <th className="table-cell text-left" key={label}>
                          {label}
                        </th>
                      ))}
                    </tr>
                  </thead>
                  <tbody>
                    {data.entries.map((entry) => (
                      <tr key={entry.id}>
                        <td className="table-cell whitespace-nowrap">
                          {new Date(entry.date).toLocaleString('en-PK', {
                            timeZone: 'Asia/Karachi',
                          })}
                        </td>
                        <td className="table-cell">
                          {entry.type.replaceAll('_', ' ')}
                          {entry.note && <p>{entry.note}</p>}
                        </td>
                        <td className="table-cell">
                          {entry.document_no ?? '—'}
                        </td>
                        <td className="table-cell whitespace-nowrap">
                          {money(entry.debit)}
                        </td>
                        <td className="table-cell whitespace-nowrap">
                          {money(entry.credit)}
                        </td>
                        <td className="table-cell whitespace-nowrap">
                          {money(entry.balance)}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </DataTable>
              </div>
              {!data.entries.length && <p>No entries in this period.</p>}
              <p className="font-bold">
                Closing balance: {money(data.closing_balance)}
              </p>
              <p>Current account balance: {money(data.customer.balance)}</p>
            </div>
          )}
        </div>
        <div className="modal-footer flex-wrap">
          {valid && link && !query.error && (
            <a
              href={link}
              target="_blank"
              rel="noopener noreferrer"
              className="btn btn-secondary btn-md"
            >
              Share summary on WhatsApp
            </a>
          )}
          <button
            type="button"
            disabled={!valid || !data || !!query.error}
            className="btn btn-primary btn-md"
            onClick={() => {
              try {
                printAccountDocument(slip.current);
              } catch (error) {
                swalConfig.error(getErrorMessage(error));
              }
            }}
          >
            Print statement
          </button>
        </div>
      </ModalShell>
    </div>
  );
}
