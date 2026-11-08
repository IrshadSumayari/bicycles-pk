import { expect, it } from 'vitest';
import { applyVariantAmount } from './variantPricing';

it('replaces every existing and new variant price while preserving identity, cost and stock', () => {
  const rows = [
    {key:'1', variantId:'v1', price:13499, cost:1900, stock:3},
    {key:'2', price:13499, cost:1900, openingStock:0},
  ];
  const changed = applyVariantAmount(rows, 'price', '3490');
  expect(changed).toEqual(rows.map(row => ({...row,price:3490})));
  expect(rows.map(row => row.price)).toEqual([13499,13499]);
});
it('applies zero and fractional costs independently of price', () => {
  const rows = [{price:3490,cost:1900}];
  expect(applyVariantAmount(rows,'price','0')).toEqual([{price:0,cost:1900}]);
  expect(applyVariantAmount(rows,'cost','1875.25')).toEqual([{price:3490,cost:1875.25}]);
});
it.each(['','  ','-1','NaN','Infinity','text'])('rejects invalid bulk amounts: %s', input => {
  expect(() => applyVariantAmount([{price:10}], 'price', input)).toThrow('Enter a valid amount');
});
