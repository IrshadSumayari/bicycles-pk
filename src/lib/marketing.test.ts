import { describe, expect, it, vi } from 'vitest';
vi.mock('./supabase', () => ({ supabase: {} }));
import { marketingCsv } from './marketing';

describe('marketing export', () => {
  it('keeps SMS numbers importable while preventing spreadsheet formulas', () => {
    const csv = marketingCsv([{ name: '=IMPORTXML("bad")', contact: '+923001234567', source: 'POS', consent_at: '2026-10-22T00:00:00Z', total_count: 1 }]);
    expect(csv).toContain('"\'=IMPORTXML(""bad"")"');
    expect(csv).toContain('"+923001234567"');
    expect(csv).not.toContain("'+923001234567");
    expect(csv).toContain('"2026-10-22T00:00:00Z"');
  });
  it('still neutralises a plus-sign formula that is not a phone number', () => {
    const csv = marketingCsv([{ name: '+SUM(A1:A9)', contact: '-1+2@x.test', source: 'POS', consent_at: null, total_count: 1 }]);
    expect(csv).toContain('"\'+SUM(A1:A9)"');
    expect(csv).toContain('"\'-1+2@x.test"');
  });
  it('quotes commas and newlines and emits a UTF-8 BOM', () => {
    const csv = marketingCsv([{ name: 'Ali,\nKhan', contact: 'ali@example.test', source: 'Website', consent_at: null, total_count: 1 }]);
    expect(csv.startsWith('\uFEFF')).toBe(true);
    expect(csv).toContain('"Ali,\nKhan"');
  });
});
