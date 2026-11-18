import { expect, it } from 'vitest';
import type { Product } from '../types';
import { inventoryMetrics, percentage } from './inventoryMetrics';

const item = (values: Partial<Product> = {}): Product => ({
  trackInventory: true, stock: 0, minStock: 2, cost: 100, ...values,
} as Product);

it('starts every inventory measure at zero for an empty store', () => {
  expect(Object.values(inventoryMetrics([], 0))).toEqual([0,0,0,0,0,0,0]);
});
it('updates measured ratios after receipts, sales and cost changes', () => {
  const before = inventoryMetrics([item(), item(), item({trackInventory:false, stock:100})], 6);
  expect(before).toMatchObject({loadedProgress:50, lowCount:0, emptyCount:2, emptyProgress:100, value:0, valuedProgress:0});
  const received = inventoryMetrics([item({stock:4}), item({stock:1}), item({trackInventory:false, stock:100})], 6);
  expect(received).toMatchObject({lowCount:1, lowProgress:50, emptyCount:0, emptyProgress:0, value:500, valuedProgress:100});
  expect(inventoryMetrics([item({stock:0}), item({stock:1, cost:0})], 2)).toMatchObject({emptyProgress:50, valuedProgress:0, value:0});
});
it('treats negative stock as unavailable and excludes services from stock valuation', () => {
  expect(inventoryMetrics([item({stock:-1}), item({trackInventory:false, stock:10})], 2))
    .toMatchObject({emptyCount:1, lowCount:0, value:0});
});
it.each([[1,0,0], [0,10,0], [3,4,75], [20,10,100], [-1,10,0], [NaN,2,0], [2,Infinity,0]])(
  'keeps percentages finite for %s / %s', (part,total,result) => expect(percentage(part,total)).toBe(result));
