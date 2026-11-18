import {Input}from'@/components/ui/input';
import { useEffect, useState } from 'react';
import { Download, RefreshCw } from 'lucide-react';
import { useQueryClient } from '@tanstack/react-query';
import { useApp } from '../../context/SupabaseAppContext';
import {
  salesService,
  type SalesSearchFilters,
  type TransactionRow,
} from '../../lib/services';
import { queryKeys } from '../../lib/queryClient';
import { rangeFor, type ReportPreset } from '../../lib/reportDates';
import { toCsv, downloadCsv } from '../../lib/csv';
import { getErrorMessage } from '../../lib/errors';
import { swalConfig } from '../../lib/sweetAlert';
import { TransactionList } from './TransactionList';
import { TransactionDetail } from './TransactionDetail';

export function TransactionsManager() {
  const { state } = useApp();
  const user = state.currentUser;
  if (!user?.active || !['admin', 'manager', 'cashier'].includes(user.role)) {
    return (
      <p className="p-6" role="status">
        Transactions are for counter staff only.
      </p>
    );
  }
  return (
    <TransactionsScreen
      key={user.id}
      userId={user.id}
      currency={state.settings.currency}
    />
  );
}

function TransactionsScreen({
  userId,
  currency,
}: {
  userId: string;
  currency: string;
}) {
  const queryClient = useQueryClient();
  const [preset, setPreset] = useState<ReportPreset | 'all'>('all');
  const [dates, setDates] = useState(() => rangeFor('today', new Date()));
  const [status, setStatus] = useState<SalesSearchFilters['status']>();
  const [method, setMethod] = useState<SalesSearchFilters['method']>();
  const [input, setInput] = useState('');
  const [q, setQ] = useState('');
  const [page, setPage] = useState(0);
  const [selected, setSelected] = useState<string | null>(null);
  const [exporting, setExporting] = useState(false);
  useEffect(() => {
    const timer = setTimeout(() => {
      setQ(input.trim());
      setPage(0);
    }, 300);
    return () => clearTimeout(timer);
  }, [input]);
  const valid =
    preset === 'all' ||
    Boolean(dates.from && dates.to && dates.from <= dates.to);
  const filters: SalesSearchFilters = {
    ...(preset === 'all' ? {} : dates),
    status,
    method,
    q: q || undefined,
  };
  const exportCsv = async () => {
    setExporting(true);
    try {
      const rows: TransactionRow[] = [];
      for (let index = 0; ; index++) {
        const batch = await salesService.search(filters, index, 200);
        const total = batch[0]?.total_count ?? 0;
        if (total > 5000 || rows.length + batch.length > 5000) {
          swalConfig.warning(
            'More than 5,000 transactions match. Narrow the dates or filters before exporting.',
          );
          return;
        }
        rows.push(...batch);
        if (batch.length === 0 || rows.length >= total) break;
      }
      downloadCsv(
        `transactions-${filters.from ?? 'all'}-${filters.to ?? 'time'}.csv`,
        toCsv(
          rows.map((row) => ({
            invoice: row.invoice_number,
            date: new Date(row.created_at).toLocaleString('en-GB', {
              timeZone: 'Asia/Karachi',
            }),
            customer: row.customer_name || 'Walk-in',
            items: row.line_count,
            total: `${currency} ${row.total.toFixed(2)}`,
            methods: row.paid_methods.join(' / ') || '—',
            status: row.status,
            cashier: row.cashier_name || '—',
            returned: `${currency} ${row.returned_amount.toFixed(2)}`,
          })),
          [
            { key: 'invoice', label: 'Invoice' },
            { key: 'date', label: 'Date (Asia/Karachi)' },
            { key: 'customer', label: 'Customer' },
            { key: 'items', label: 'Lines' },
            { key: 'total', label: 'Total' },
            { key: 'methods', label: 'Payments' },
            { key: 'status', label: 'Status' },
            { key: 'cashier', label: 'Cashier' },
            { key: 'returned', label: 'Returned' },
          ],
        ),
      );
    } catch (error) {
      swalConfig.error(getErrorMessage(error));
    } finally {
      setExporting(false);
    }
  };
  return (
    <div className="p-4 lg:p-6 space-y-5 bg-lightgray min-h-full">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <p className="text-sm text-bodytext">Shop dates in Asia/Karachi</p>
        </div>
        <div className="flex gap-2">
          <button
            type="button"
            className="btn btn-secondary btn-md"
            onClick={() =>
              void queryClient.invalidateQueries({
                queryKey: queryKeys.transactions,
              })
            }
          >
            <RefreshCw className="h-4 w-4" />
            Refresh
          </button>
          <button
            type="button"
            className="btn btn-primary btn-md"
            disabled={!valid || exporting || input.trim() !== q}
            onClick={() => void exportCsv()}
          >
            <Download className="h-4 w-4" />
            {exporting ? 'Exporting…' : 'Export CSV'}
          </button>
        </div>
      </div>
      <fieldset
        disabled={exporting}
        className="card p-4 flex flex-wrap items-end gap-3"
      >
        <label className="text-sm font-medium flex-1 min-w-56">
          Search
          <Input
            className="input block mt-1"
            value={input}
            onChange={(e) => setInput(e.target.value)}
            placeholder="Invoice, customer, phone or SKU"
          />
        </label>
        <label className="text-sm font-medium">
          Status
          <select
            aria-label="Status"
            className="select block mt-1"
            value={status ?? ''}
            onChange={(e) => {
              setStatus(
                (e.target.value as SalesSearchFilters['status']) || undefined,
              );
              setPage(0);
            }}
          >
            <option value="">All statuses</option>
            {['completed', 'credit', 'draft', 'returned', 'refunded'].map(
              (value) => (
                <option key={value} value={value}>
                  {value}
                </option>
              ),
            )}
          </select>
        </label>
        <label className="text-sm font-medium">
          Payment method
          <select
            aria-label="Payment method"
            className="select block mt-1"
            value={method ?? ''}
            onChange={(e) => {
              setMethod(
                (e.target.value as SalesSearchFilters['method']) || undefined,
              );
              setPage(0);
            }}
          >
            <option value="">All payments</option>
            {['cash', 'card', 'digital', 'credit', 'exchange'].map((value) => (
              <option key={value} value={value}>
                {value}
              </option>
            ))}
          </select>
        </label>
        <label className="text-sm font-medium">
          Period
          <select
            aria-label="Period"
            className="select block mt-1"
            value={preset}
            onChange={(e) => {
              const value = e.target.value as ReportPreset | 'all';
              setPreset(value);
              setPage(0);
              if (value !== 'custom' && value !== 'all')
                setDates(rangeFor(value, new Date()));
            }}
          >
            <option value="all">All time</option>
            <option value="today">Today</option>
            <option value="yesterday">Yesterday</option>
            <option value="this_week">This week</option>
            <option value="this_month">This month</option>
            <option value="last_month">Last month</option>
            <option value="custom">Custom</option>
          </select>
        </label>
        {preset === 'custom' && (
          <>
            <label className="text-sm font-medium">
              From
              <Input
                type="date"
                className="input block mt-1"
                value={dates.from}
                max={dates.to || undefined}
                onChange={(e) => {
                  setDates({ ...dates, from: e.target.value });
                  setPage(0);
                }}
              />
            </label>
            <label className="text-sm font-medium">
              To
              <Input
                type="date"
                className="input block mt-1"
                value={dates.to}
                min={dates.from || undefined}
                onChange={(e) => {
                  setDates({ ...dates, to: e.target.value });
                  setPage(0);
                }}
              />
            </label>
          </>
        )}
      </fieldset>
      {valid ? (
        <TransactionList
          userId={userId}
          currency={currency}
          filters={filters}
          page={page}
          onPage={setPage}
          onSelect={setSelected}
        />
      ) : (
        <p className="card p-5 text-warning" role="alert">
          Choose both dates, with From on or before To.
        </p>
      )}
      {selected && (
        <TransactionDetail
          key={selected}
          id={selected}
          userId={userId}
          currency={currency}
          onClose={() => setSelected(null)}
        />
      )}
    </div>
  );
}
