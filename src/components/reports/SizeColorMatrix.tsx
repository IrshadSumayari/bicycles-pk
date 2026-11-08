import { useQuery } from '@tanstack/react-query';
import { reportsService } from '../../lib/services';
import { queryKeys } from '../../lib/queryClient';
import type { CsvValue } from '../../lib/csv';
import { ReportStatus } from './ReportStatus';
import { ReportTable } from './ReportTable';
import type { ReportProps } from './reportTypes';

export function SizeColorMatrix({
  from,
  to,
  userId,
  styleId,
  styleName,
}: ReportProps & { styleId: string; styleName: string }) {
  const query = useQuery({
    queryKey: queryKeys.reports('matrix', from, to, { userId, styleId }),
    queryFn: () => reportsService.sizeColorMatrix(from, to, styleId),
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
  const sizes = [...new Set(query.data.map((row) => row.size))];
  const colors = [...new Set(query.data.map((row) => row.color))];
  const rows: Record<string, CsvValue>[] = sizes.map((size) => {
    const row: Record<string, CsvValue> = { size: size || 'Unspecified' };
    colors.forEach((color, index) => {
      const cell = query.data.find(
        (item) => item.size === size && item.color === color,
      );
      row[`color${index}`] = cell ? `${cell.sold} / ${cell.on_hand}` : '—';
    });
    return row;
  });
  return (
    <div className="space-y-3">
      <p className="text-sm text-bodytext">
        Each cell shows sold / on hand. Sold is net of returns for the period;
        on hand is current stock.
      </p>
      <ReportTable
        title={`Size × color: ${styleName}`}
        filename={`size-color-${styleId}-${from}-${to}.csv`}
        rows={rows}
        columns={[
          { key: 'size', label: 'Size' },
          ...colors.map((color, index) => ({
            key: `color${index}`,
            label: color || 'Unspecified',
          })),
        ]}
      />
    </div>
  );
}
