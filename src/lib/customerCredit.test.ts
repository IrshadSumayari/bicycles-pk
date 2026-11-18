import { describe, expect, it } from 'vitest';
import { customerStatementLink } from './customerCredit';

describe('customerStatementLink', () => {
  it('encodes a short summary and normalizes phone punctuation', () => {
    const result = customerStatementLink(
      '+92 300-1112233',
      'علی & Sons',
      'Shop',
      '2026-01-01',
      '2026-01-31',
      125.5,
      'PKR',
    )!;
    expect(result.startsWith('https://wa.me/923001112233?text=')).toBe(true);
    expect(decodeURIComponent(result.split('?text=')[1])).toContain(
      'علی & Sons',
    );
    expect(decodeURIComponent(result.split('?text=')[1])).toContain(
      'closing balance PKR 125.50',
    );
  });
  it('omits sharing when no valid phone is available', () => {
    expect(
      customerStatementLink(null, 'Ali', 'Shop', '', '', 0, 'PKR'),
    ).toBeNull();
    expect(
      customerStatementLink('123', 'Ali', 'Shop', '', '', 0, 'PKR'),
    ).toBeNull();
  });
});
