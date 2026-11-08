import { describe, expect, it } from 'vitest';
import { slugify, validateImageFile } from './images';
describe('image helpers', () => {
  it.each([
    ['Classic Shirt', 'classic-shirt'],
    ['  Sale!!! Blue / White  ', 'sale-blue-white'],
    ['عید Eid Kurta نیا', 'eid-kurta'],
    ['اردو', ''],
    ['---', ''],
    ['A_B.C 42', 'a-b-c-42'],
  ])('slugifies %s', (text, expected) => expect(slugify(text)).toBe(expected));
  it('caps at 80 ASCII characters and trims a cut-off hyphen', () => {
    expect(slugify('A'.repeat(79) + ' B')).toBe('a'.repeat(79));
    expect(slugify('abc '.repeat(40)).length).toBeLessThanOrEqual(80);
    expect(slugify('X'.repeat(100))).toHaveLength(80);
  });
  it('accepts images up to the exact input limit', () => {
    expect(() =>
      validateImageFile({ type: 'image/png', size: 10 * 1024 * 1024 }),
    ).not.toThrow();
  });
  it('rejects oversized files and non-images before decoding', () => {
    expect(() =>
      validateImageFile({ type: 'image/jpeg', size: 10 * 1024 * 1024 + 1 }),
    ).toThrow('10 MB');
    expect(() =>
      validateImageFile({ type: 'application/pdf', size: 20 }),
    ).toThrow('image file');
    expect(() => validateImageFile({ type: '', size: 20 })).toThrow(
      'image file',
    );
  });
});
