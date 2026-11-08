import {Chart}from'@/components/dashboard/Chart';
import { useQuery } from '@tanstack/react-query';
import { reportsService } from '../../lib/services';
import { queryKeys } from '../../lib/queryClient';
import type { Database } from '../../lib/database.types';
import { ReportKpis } from './ReportKpis';
import { ReportStatus } from './ReportStatus';
import { ReportTable, type ReportColumn } from './ReportTable';
import type { ReportProps } from './reportTypes';

type SalesRow =
  Database['public']['Functions']['report_sales_summary']['Returns'][number];

export function SalesReport({ from, to, currency, userId }: ReportProps) {
  const query = useQuery({
    queryKey: queryKeys.reports('sales', from, to, { userId }),
    queryFn: () => reportsService.salesSummary(from, to),
    staleTime: 0,
  });
  if (query.isPending || query.isError)
    return (
      <ReportStatus
        loading={query.isPending}
        error={query.error}
        retry={() => void query.refetch()}
      />
    );
  const rows = query.data;
  const money = (value: number | string) =>
    `${currency} ${Number(value).toFixed(2)}`;
  const totals = rows.reduce(
    (sum, row) => ({
      net: sum.net + row.net_after_returns,
      tax: sum.tax + row.tax - row.returns_tax,
      returns: sum.returns + row.returns,
      margin: sum.margin + row.margin,
    }),
    { net: 0, tax: 0, returns: 0, margin: 0 },
  );
  const columns: ReportColumn<SalesRow>[] = [
    { key: 'day', label: 'Day' },
    { key: 'invoices', label: 'Invoices' },
    { key: 'gross', label: 'Gross', format: money },
    { key: 'discounts', label: 'Discounts', format: money },
    { key: 'net_sales', label: 'Net sales', format: money },
    { key: 'tax', label: 'Tax', format: money },
    { key: 'returns', label: 'Returns', format: money },
    { key: 'returns_tax', label: 'Returned tax', format: money },
    { key: 'net_after_returns', label: 'Net after returns', format: money },
    { key: 'cost', label: 'Cost', format: money },
    { key: 'margin', label: 'Margin', format: money },
  ];

  return (
    <div className="space-y-5">
      <ReportKpis
        items={[
          { label: 'Net after returns', value: money(totals.net) },
          { label: 'Tax after refunds', value: money(totals.tax) },
          { label: 'Returns before tax', value: money(totals.returns) },
          { label: 'Margin', value: money(totals.margin) },
          {
            label: 'Margin %',
            value:
              totals.net === 0
                ? '—'
                : `${((totals.margin / totals.net) * 100).toFixed(2)}%`,
          },
        ]}
      />
      {rows.length > 0 && (
        <section
          className="card p-5"
          aria-label="Daily net after returns chart"
        >
          <h2 className="font-semibold mb-4">Daily net after returns</h2>
          <Chart type="bar" height={300} series={[{name:'Net after returns',data:rows.map(r=>r.net_after_returns)}]} options={{dataLabels:{enabled:false},xaxis:{categories:rows.map(r=>r.day)},yaxis:{labels:{formatter:n=>money(n)}}}}/>
        </section>
      )}
      <ReportTable
        title="Daily sales"
        filename={`sales-${from}-${to}.csv`}
        rows={rows}
        columns={columns}
      />
    </div>
  );
}
