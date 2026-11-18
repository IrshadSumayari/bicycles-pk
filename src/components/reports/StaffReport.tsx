import { useQuery } from '@tanstack/react-query';
import { reportsService } from '../../lib/services';
import { queryKeys } from '../../lib/queryClient';
import { ReportStatus } from './ReportStatus';
import { ReportTable } from './ReportTable';
import type { ReportProps } from './reportTypes';

export function StaffReport({ from, to, currency, userId }: ReportProps) {
  const query = useQuery({
    queryKey: queryKeys.reports('staff', from, to, { userId }),
    queryFn: () => reportsService.staffSales(from, to),
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
  const money = (value: string | number) =>
    `${currency} ${Number(value).toFixed(2)}`;
  return (
    <ReportTable
      title="Staff sales"
      filename={`staff-${from}-${to}.csv`}
      rows={query.data}
      columns={[
        { key: 'name', label: 'Staff member' },
        { key: 'invoices', label: 'Invoices' },
        { key: 'net_sales', label: 'Net sales', format: money },
        { key: 'returns', label: 'Returns', format: money },
        { key: 'discounts', label: 'Discounts', format: money },
      ]}
    />
  );
}
