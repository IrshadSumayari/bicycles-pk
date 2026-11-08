import { describe, expect, it } from 'vitest';
import { sectionById } from '../../shared/bicycles';
import { ALL_CATEGORIES, inventoryCategoryFilter, inventoryCategoryOptions, newStyleCategory } from './inventoryCategory';

describe('inventory category filter', () => {
  it('starts the Kids section on every kids category', () => {
    const options = inventoryCategoryOptions('kids', ['Helmets']);
    expect(options[0]).toBe('All kids');
    expect(options).toContain('Balance Bikes');
    expect(options).not.toContain('Helmets');
    expect(inventoryCategoryFilter('All kids')).toEqual({ categories: sectionById('kids').categories.map(c => c.name) });
  });
  it('keeps exact single-category filters and the unfiltered Inventory view', () => {
    expect(inventoryCategoryFilter('Road Bikes')).toEqual({ category: 'Road Bikes' });
    expect(inventoryCategoryFilter('Bicycles')).toEqual({ category: 'Bicycles' });
    expect(inventoryCategoryFilter(ALL_CATEGORIES)).toEqual({});
    expect(inventoryCategoryOptions(undefined, ['Helmets', 'Locks'])).toEqual([ALL_CATEGORIES, 'Helmets', 'Locks']);
  });
  it('starts new styles in the chosen or general section category', () => {
    expect(newStyleCategory('accessories', 'Locks')).toBe('Locks');
    expect(newStyleCategory('accessories', 'All accessories')).toBe('Accessories');
    expect(newStyleCategory(undefined, 'Locks')).toBeUndefined();
  });
});
