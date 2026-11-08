import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import {
  reportsService,
  stylesService,
  type ReportGroup,
} from '../../lib/services';
import { queryKeys } from '../../lib/queryClient';
import { ReportStatus } from './ReportStatus';
import { ReportTable } from './ReportTable';
import { SizeColorMatrix } from './SizeColorMatrix';
import type { ReportProps } from './reportTypes';

export function ProductsReport(props: ReportProps) {
  const { from, to, currency, userId } = props;
  const [group, setGroup] = useState<ReportGroup>('style');
  const [styleId, setStyleId] = useState('');
  const query = useQuery({
    queryKey: queryKeys.reports('products', from, to, {
      userId,
      group,
      limit: 50,
    }),
    queryFn: () => reportsService.topItems(from, to, group, 50),
    staleTime: 0,
  });
  const styles = useQuery({
    queryKey: queryKeys.reports('styles', from, to, { userId }),
    queryFn: () => stylesService.listOptions(),
  });
  const money = (value: string | number) =>
    `${currency} ${Number(value).toFixed(2)}`;
  const styleName =
    styles.data?.find((style) => style.id === styleId)?.name ??
    'Selected style';
  return (
    <div className="space-y-5">
      <div className="card p-4 flex flex-wrap items-end gap-4">
        <label className="space-y-1 text-sm font-medium">
          Group products by
          <select
            className="select block"
            value={group}
            onChange={(event) => setGroup(event.target.value as ReportGroup)}
          >
            <option value="style">Style</option>
            <option value="variant">Variant</option>
            <option value="category">Category</option>
            <option value="size">Size</option>
            <option value="color">Color</option>
          </select>
        </label>
        <label className="space-y-1 text-sm font-medium">
          Size × color for style
          <select
            className="select block max-w-sm"
            value={styleId}
            disabled={styles.isPending || styles.isError}
            onChange={(event) => setStyleId(event.target.value)}
          >
            <option value="">
              {styles.isPending ? 'Loading styles…' : 'Choose a style'}
            </option>
            {styles.data?.map((style) => (
              <option key={style.id} value={style.id}>
                {style.name} ({style.code})
              </option>
            ))}
          </select>
        </label>
      </div>
      {styles.isError && (
        <ReportStatus
          loading={false}
          error={styles.error}
          retry={() => void styles.refetch()}
        />
      )}
      <p className="text-sm text-bodytext">
        Top 50 by net sales before tax, after returns.
        {group === 'style'
          ? ' Select a style name to view its size and color demand.'
          : ''}
      </p>
      {query.isPending || query.isError ? (
        <ReportStatus
          loading={query.isPending}
          error={query.error}
          retry={() => void query.refetch()}
        />
      ) : (
        <ReportTable
          title="Top products"
          filename={`products-${group}-${from}-${to}.csv`}
          rows={query.data}
          onSelect={
            group === 'style'
              ? (row) => {
                  if (row.key) setStyleId(row.key);
                }
              : undefined
          }
          columns={[
            { key: 'label', label: 'Product group' },
            { key: 'quantity', label: 'Quantity' },
            { key: 'net', label: 'Net sales', format: money },
            { key: 'cost', label: 'Cost', format: money },
            { key: 'margin', label: 'Margin', format: money },
          ]}
        />
      )}
      {styleId && (
        <SizeColorMatrix
          key={styleId}
          {...props}
          styleId={styleId}
          styleName={styleName}
        />
      )}
    </div>
  );
}
