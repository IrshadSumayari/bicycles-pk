import { describe, expect, it } from 'vitest';
import { jewelleryCategories } from '../../shared/jewellery';
import { ALL_CATEGORIES, ALL_JEWELLERY, inventoryCategoryFilter, inventoryCategoryOptions } from './inventoryCategory';

describe('inventory category filter', () => {
  it('starts the Jewellery section on every jewellery category', () => {
    const options = inventoryCategoryOptions('jewellery', ['Bras']);
    expect(options[0]).toBe(ALL_JEWELLERY);
    expect(options).toContain('Rings');
    expect(options).not.toContain('Bras');
    expect(inventoryCategoryFilter(ALL_JEWELLERY)).toEqual({ categories: jewelleryCategories.map(c => c.name) });
  });
  it('keeps exact single-category filters and the unfiltered Inventory view', () => {
    expect(inventoryCategoryFilter('Rings')).toEqual({ category: 'Rings' });
    expect(inventoryCategoryFilter('Jewellery')).toEqual({ category: 'Jewellery' });
    expect(inventoryCategoryFilter(ALL_CATEGORIES)).toEqual({});
    expect(inventoryCategoryOptions(undefined, ['Bras', 'Rings'])).toEqual([ALL_CATEGORIES, 'Bras', 'Rings']);
  });
});
