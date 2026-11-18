import {Input}from'@/components/ui/input';
import { useState } from 'react';
import { productLabel } from '../../types';
import { useProductSearch, useProductsById } from '../../lib/hooks/useProducts';
import { ReportStatus } from '../reports/ReportStatus';

export function ProductPicker({
  selected,
  onChange,
  label,
}: {
  selected: string[];
  onChange: (ids: string[]) => void;
  label: string;
}) {
  const [q, setQ] = useState('');
  const search = useProductSearch({ q, limit: 20 }, !!q.trim());
  const saved = useProductsById(selected);
  const products = [
    ...new Map(
      [
        ...(saved.data ?? []),
        ...(q.trim() ? (search.data?.rows ?? []) : []),
      ].map((p) => [p.id, p]),
    ).values(),
  ];
  return (
    <div className="space-y-2">
      <Input
        aria-label={label}
        placeholder="Search products by name or SKU"
        className="input"
        value={q}
        onChange={(e) => setQ(e.target.value)}
      />
      <ReportStatus
        loading={search.isFetching || saved.isFetching}
        error={search.error ?? saved.error}
        retry={() => {
          void search.refetch();
          void saved.refetch();
        }}
      />
      <div className="max-h-48 overflow-y-auto space-y-1">
        {products.map((product) => (
          <label
            key={product.id}
            className="flex gap-2 items-center p-2 border rounded-lg"
          >
            <Input
              type="checkbox"
              checked={selected.includes(product.id)}
              onChange={() =>
                onChange(
                  selected.includes(product.id)
                    ? selected.filter((id) => id !== product.id)
                    : [...selected, product.id],
                )
              }
            />
            <span>
              {productLabel(product)} · {product.sku}
            </span>
          </label>
        ))}
        {selected
          .filter((id) => !products.some((p) => p.id === id))
          .map((id) => (
            <button
              type="button"
              key={id}
              className="btn btn-secondary btn-sm"
              onClick={() => onChange(selected.filter((key) => key !== id))}
            >
              Remove unavailable product {id}
            </button>
          ))}
        {!!q.trim() && !search.isFetching && !search.data?.rows.length && (
          <p className="text-sm text-bodytext">No matching products</p>
        )}
      </div>
    </div>
  );
}
