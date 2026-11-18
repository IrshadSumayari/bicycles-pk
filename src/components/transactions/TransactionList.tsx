import {StatusBadge}from'@/components/shared/StatusBadge';
import {DataTable}from'@/components/shared/DataTable';
import { keepPreviousData, useQuery } from '@tanstack/react-query';
import { salesService, type SalesSearchFilters } from '../../lib/services';
import { queryKeys } from '../../lib/queryClient';
import { getErrorMessage } from '../../lib/errors';

export function TransactionList({
  userId,
  currency,
  filters,
  page,
  onPage,
  onSelect,
}: {
  userId: string;
  currency: string;
  filters: SalesSearchFilters;
  page: number;
  onPage: (page: number) => void;
  onSelect: (id: string) => void;
}) {
  const query = useQuery({
    queryKey: queryKeys.transactionList(userId, filters, page),
    queryFn: async () => {
      const rows = await salesService.search(filters, page);
      // A window count has no row to attach to on an emptied last page.
      const total =
        rows[0]?.total_count ??
        (page > 0
          ? (await salesService.search(filters, 0, 1))[0]?.total_count
          : 0) ??
        0;
      return { rows, total };
    },
    placeholderData: keepPreviousData,
    staleTime: 0,
  });
  if (query.isPending)
    return (
      <p role="status" className="card p-5 text-bodytext">
        Loading transactions…
      </p>
    );
  if (query.isError)
    return (
      <div role="alert" className="card p-5 space-y-3">
        <p className="text-error">{getErrorMessage(query.error)}</p>
        <button
          className="btn btn-secondary btn-md"
          onClick={() => void query.refetch()}
        >
          Try again
        </button>
      </div>
    );
  const { rows, total } = query.data;
  return (
    <div className="card overflow-hidden" aria-busy={query.isFetching}>
      {query.isFetching && (
        <p role="status" className="px-4 py-2 text-sm text-bodytext">
          Updating transactions…
        </p>
      )}
      <div className="overflow-x-auto">
        <DataTable className="table" aria-label="Transactions">
          <thead className="table-header">
            <tr>
              {[
                'Invoice',
                'Date (Asia/Karachi)',
                'Customer',
                'Lines',
                'Total',
                'Payments',
                'Status',
                'Cashier',
                'Returned',
              ].map((label) => (
                <th key={label} scope="col" className="table-header-cell">
                  {label}
                </th>
              ))}
            </tr>
          </thead>
          <tbody className="divide-y divide-border bg-card">
            {rows.length === 0 && (
              <tr>
                <td
                  colSpan={9}
                  className="table-cell text-center text-bodytext"
                >
                  No transactions match these filters.
                </td>
              </tr>
            )}
            {rows.map((row) => (
              <tr key={row.id} className="table-row">
                <td className="table-cell">
                  <button
                    type="button"
                    className="text-primary underline font-medium"
                    disabled={query.isPlaceholderData}
                    onClick={() => onSelect(row.id)}
                  >
                    {row.invoice_number}
                  </button>
                </td>
                <td className="table-cell">
                  {new Date(row.created_at).toLocaleString('en-GB', {
                    timeZone: 'Asia/Karachi',
                  })}
                </td>
                <td className="table-cell">{row.customer_name || 'Walk-in'}</td>
                <td className="table-cell">{row.line_count}</td>
                <td className="table-cell">
                  {currency} {row.total.toFixed(2)}
                </td>
                <td className="table-cell capitalize">
                  {row.paid_methods.join(' / ') || '—'}
                </td>
                <td className="table-cell capitalize"><StatusBadge status={row.status}>{row.status}</StatusBadge></td>
                <td className="table-cell">{row.cashier_name || '—'}</td>
                <td className="table-cell">
                  {currency} {row.returned_amount.toFixed(2)}
                </td>
              </tr>
            ))}
          </tbody>
        </DataTable>
      </div>
      <div className="p-4 border-t border-border flex flex-wrap justify-between items-center gap-3">
        <p className="text-sm text-bodytext">
          {query.isPlaceholderData
            ? 'Updating page…'
            : `Showing ${rows.length ? page * 50 + 1 : 0}–${rows.length ? page * 50 + rows.length : 0} of ${total}`}
        </p>
        <div className="flex gap-2">
          {page > 0 && rows.length === 0 && (
            <button
              className="btn btn-secondary btn-md"
              onClick={() => onPage(0)}
            >
              First page
            </button>
          )}
          <button
            className="btn btn-secondary btn-md"
            disabled={page === 0 || query.isPlaceholderData}
            onClick={() => onPage(page - 1)}
          >
            Previous
          </button>
          <button
            className="btn btn-secondary btn-md"
            disabled={(page + 1) * 50 >= total || query.isPlaceholderData}
            onClick={() => onPage(page + 1)}
          >
            Next
          </button>
        </div>
      </div>
    </div>
  );
}
