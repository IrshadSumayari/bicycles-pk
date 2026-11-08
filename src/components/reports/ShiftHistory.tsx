import {Input}from'@/components/ui/input';
import {StatusBadge}from'@/components/shared/StatusBadge';
import {DataTable}from'@/components/shared/DataTable';
import { useUsers } from '../../lib/hooks/useUsers';
import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import {
  shiftsService,
  type ShiftHistoryRow,
  type ShiftFilters,
} from '../../lib/services';
import { queryKeys } from '../../lib/queryClient';
import { downloadCsv, toCsv } from '../../lib/csv';
import { ReportStatus } from './ReportStatus';
import { ShiftDetailModal } from './ShiftDetailModal';
import { ForceCloseModal } from './ForceCloseModal';

const columns = [
  ['session_no', 'Shift'],
  ['user_name', 'Cashier'],
  ['opened_at', 'Opened (Asia/Karachi)'],
  ['status', 'Status'],
  ['opening_float', 'Opening float'],
  ['cash_sales', 'Cash sales / deposits'],
  ['refunds', 'Refunds'],
  ['cash_in', 'Cash in'],
  ['cash_out', 'Cash out'],
  ['expected_cash', 'Expected cash'],
  ['counted_cash', 'Counted cash'],
  ['variance', 'Difference'],
  ['closed_by_name', 'Closed by'],
  ['closing_notes', 'Notes'],
] as const;

export function ShiftHistory({
  from,
  to,
  userId,
  currency,
  personal = false,
}: {
  from?: string;
  to?: string;
  userId: string;
  currency: string;
  personal?: boolean;
}) {
  const [cashier, setCashier] = useState('');
  const [status, setStatus] = useState('');
  const [onlyVariance, setOnlyVariance] = useState(false);
  const [page, setPage] = useState(0);
  const [detailId, setDetailId] = useState<string | null>(null);
  const [closing, setClosing] = useState<ShiftHistoryRow | null>(null);
  const filters: ShiftFilters = personal
    ? { user_id: userId }
    : {
        from,
        to,
        user_id: cashier || undefined,
        status: status || undefined,
        only_variance: onlyVariance,
      };
  const limit = personal ? 30 : 50;
  const query = useQuery({
    queryKey: queryKeys.shiftList(userId, { ...filters, limit }, page),
    queryFn: () => shiftsService.list(filters, page, limit),
  });
  const users = useUsers(!personal);
  const rows = query.data ?? [];
  const total = rows[0]?.total_count ?? 0;
  const money = (value: number | null) =>
    value == null ? '—' : `${currency} ${value.toFixed(2)}`;
  const time = (value: string) =>
    new Date(value).toLocaleString('en-PK', { timeZone: 'Asia/Karachi' });
  function exportCsv() {
    downloadCsv(
      'cash-shifts.csv',
      toCsv(
        rows.map((row) =>
          Object.fromEntries(
            columns.map(([key]) => [
              key,
              key === 'opened_at' ? time(row.opened_at) : row[key],
            ]),
          ),
        ),
        columns.map(([key, label]) => ({ key, label })),
      ),
    );
  }
  return (
    <div className="space-y-4 min-w-0">
      <div className="card p-4 flex flex-wrap items-end gap-4">
        {personal ? (
          <p>Your latest 30 shifts · Read only</p>
        ) : (
          <>
            <label className="text-sm">
              Cashier
              <select
                aria-label="Cashier"
                className="select block"
                value={cashier}
                onChange={(e) => {
                  setCashier(e.target.value);
                  setPage(0);
                }}
              >
                <option value="">All cashiers</option>
                {users.data?.map((u) => (
                  <option key={u.id} value={u.id}>
                    {u.name}
                    {u.active ? '' : ' (inactive)'}
                  </option>
                ))}
              </select>
            </label>
            <label className="text-sm">
              Status
              <select
                aria-label="Shift status"
                className="select block"
                value={status}
                onChange={(e) => {
                  setStatus(e.target.value);
                  setPage(0);
                }}
              >
                <option value="">All statuses</option>
                <option value="open">Open</option>
                <option value="closed">Closed</option>
              </select>
            </label>
            <label className="text-sm flex items-center gap-2 py-3">
              <Input
                type="checkbox"
                checked={onlyVariance}
                onChange={(e) => {
                  setOnlyVariance(e.target.checked);
                  setPage(0);
                }}
              />
              Only with difference
            </label>
          </>
        )}
        <button
          type="button"
          className="btn btn-primary btn-md ml-auto"
          disabled={!rows.length || query.isFetching || !!query.error}
          onClick={exportCsv}
        >
          Export CSV
        </button>
      </div>
      {users.error && !personal && (
        <ReportStatus
          loading={false}
          error={users.error}
          retry={() => void users.refetch()}
        />
      )}
      <ReportStatus
        loading={query.isPending}
        error={query.error}
        retry={() => void query.refetch()}
      />
      {!query.isPending && !query.error && (
        <div className="card overflow-hidden">
          <div className="overflow-x-auto">
            <DataTable className="table w-full">
              <thead className="table-header">
                <tr>
                  {[
                    'Shift / opened',
                    'Cashier',
                    'Status',
                    'Expected',
                    'Counted',
                    'Difference',
                    'Actions',
                  ].map((label) => (
                    <th
                      className="table-cell text-left whitespace-nowrap"
                      key={label}
                    >
                      {label}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {rows.map((row) => (
                  <tr
                    key={row.id}
                    className="hover:bg-lightgray cursor-pointer"
                    onClick={() => setDetailId(row.id)}
                  >
                    <td className="table-cell whitespace-nowrap">
                      <button
                        className="text-primary underline"
                        type="button"
                        onClick={(e) => {
                          e.stopPropagation();
                          setDetailId(row.id);
                        }}
                      >
                        {row.session_no}
                      </button>
                      <p className="text-xs text-bodytext">
                        {time(row.opened_at)}
                      </p>
                    </td>
                    <td className="table-cell">{row.user_name}</td>
                    <td className="table-cell capitalize"><StatusBadge status={row.status}>{row.status}</StatusBadge></td>
                    <td className="table-cell whitespace-nowrap">
                      {money(row.expected_cash)}
                    </td>
                    <td className="table-cell whitespace-nowrap">
                      {money(row.counted_cash)}
                    </td>
                    <td className="table-cell whitespace-nowrap">
                      {money(row.variance)}
                      {row.over_limit && (
                        <span className="block rounded bg-lighterror px-2 py-1 text-error font-semibold text-xs">
                          Over alert limit
                        </span>
                      )}
                    </td>
                    <td className="table-cell">
                      {!personal &&
                        row.status === 'open' &&
                        row.user_id !== userId && (
                          <button
                            type="button"
                            className="btn btn-secondary btn-sm whitespace-nowrap"
                            onClick={(e) => {
                              e.stopPropagation();
                              setClosing(row);
                            }}
                          >
                            Close for cashier
                          </button>
                        )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </DataTable>
          </div>
          {!rows.length && (
            <p className="p-5 text-bodytext">
              No shifts found for these filters.
            </p>
          )}
          <div className="p-4 flex flex-wrap items-center gap-3 text-sm">
            <p>
              {personal
                ? `${rows.length} recent shifts`
                : `${total} shifts · Page ${page + 1}`}{' '}
              · CSV exports this page
            </p>
            {!personal && (
              <>
                <button
                  type="button"
                  className="btn btn-secondary btn-sm ml-auto"
                  disabled={!page || query.isFetching}
                  onClick={() => setPage(page - 1)}
                >
                  Previous
                </button>
                <button
                  type="button"
                  className="btn btn-secondary btn-sm"
                  disabled={(page + 1) * limit >= total || query.isFetching}
                  onClick={() => setPage(page + 1)}
                >
                  Next
                </button>
              </>
            )}
          </div>
        </div>
      )}
      {detailId && (
        <ShiftDetailModal
          id={detailId}
          userId={userId}
          currency={currency}
          onClose={() => setDetailId(null)}
        />
      )}
      {closing && (
        <ForceCloseModal
          key={closing.id}
          shift={closing}
          onClose={() => setClosing(null)}
        />
      )}
    </div>
  );
}
