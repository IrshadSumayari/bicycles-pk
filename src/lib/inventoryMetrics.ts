import type { Product } from '../types';

export function percentage(part: number, total: number): number {
  return Number.isFinite(part) && Number.isFinite(total) && total > 0
    ? Math.min(100, Math.max(0, part / total * 100)) : 0;
}

export function inventoryMetrics(products: Product[], total: number) {
  const tracked = products.filter(p => p.trackInventory);
  const low = tracked.filter(p => p.stock > 0 && p.stock <= p.minStock);
  const empty = tracked.filter(p => p.stock <= 0);
  const valued = tracked.filter(p => p.stock > 0 && p.cost > 0);
  return {
    lowCount: low.length, emptyCount: empty.length,
    value: tracked.reduce((sum, p) => sum + Math.max(0, p.stock) * p.cost, 0),
    loadedProgress: percentage(products.length, total),
    lowProgress: percentage(low.length, tracked.length),
    emptyProgress: percentage(empty.length, tracked.length),
    valuedProgress: percentage(valued.length, tracked.length),
  };
}
