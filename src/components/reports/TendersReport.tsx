import { useQuery } from '@tanstack/react-query';
import { reportsService } from '../../lib/services';
import { queryKeys } from '../../lib/queryClient';
import { ReportStatus } from './ReportStatus';
import { ReportTable } from './ReportTable';
import type { ReportProps } from './reportTypes';

export function TendersReport({ from, to, currency, userId }: ReportProps) {
  const query = useQuery({
    queryKey: queryKeys.reports('payments', from, to, { userId }),
    queryFn: () => reportsService.tenders(from, to),
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
      title="Payments"
      filename={`payments-${from}-${to}.csv`}
      rows={query.data}
      columns={[
        { key: 'method', label: 'Method' },
        { key: 'money_in', label: 'Money in', format: money },
        { key: 'money_out', label: 'Money out', format: money },
        { key: 'net', label: 'Net', format: money },
        { key: 'count', label: 'Payments' },
      ]}
    />
  );
}
