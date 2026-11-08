import { describe, it, expect } from 'vitest';
import { buildBalancePlan, importPhone } from './goLiveImport';
describe('go-live CSV validation', () => {
  it('reuses quoted CSV parsing, BOM and Urdu without losing notes', () => {
    const plan = buildBalancePlan(
      '\ufeffname,phone,amount,note\r\nعلی,03001234567,125.50,"Paper, ""old""\nbook"',
    );
    expect(plan.errors).toEqual([]);
    expect(plan.records[0]).toEqual({
      name: 'علی',
      phone: '03001234567',
      amount: 125.5,
      note: 'Paper, "old"\nbook',
    });
  });
  it('normalises local, international and spaced phones consistently', () => {
    for (const value of [
      '0300 1234567',
      '923001234567',
      '00923001234567',
      '+923001234567',
      '3001234567',
    ])
      expect(importPhone(value)).toBe('+923001234567');
    expect(importPhone('12')).toBeNull();
  });
  it('reports missing headers and row-specific balance errors', () => {
    expect(buildBalancePlan('name\nAli').errors[0].row).toBe(1);
    const plan = buildBalancePlan(
      'name,phone,amount,note\n,12,1.001,\nAli,03001234567,-1,',
    );
    expect(plan.errors.filter((e) => e.row === 2)).toHaveLength(3);
    expect(plan.errors.some((e) => e.row === 3)).toBe(true);
  });
  it.each(['0', 'NaN', 'Infinity', '1e3', '1000000000000', '1.111'])(
    'refuses invalid debt amount %s',
    (amount) => {
      expect(
        buildBalancePlan(`name,phone,amount,note\nAli,03001234567,${amount},`)
          .errors.length,
      ).toBeGreaterThan(0);
    },
  );
  it('rejects empty files, duplicate columns and broken row shapes', () => {
    expect(
      buildBalancePlan(
        'name,phone,amount,note\nAli,03001234567,1,"unfinished',
      ).errors.some((e) => e.message.includes('not closed')),
    ).toBe(true);
    expect(buildBalancePlan('').errors.length).toBeGreaterThan(0);
    expect(
      buildBalancePlan(
        'name,phone,amount,note,note\nAli,03001234567,1,,',
      ).errors.some((e) => e.message.includes('unique')),
    ).toBe(true);
    expect(
      buildBalancePlan('name,phone,amount,note\nAli,03001234567,1').errors.some(
        (e) => e.message.includes('cells'),
      ),
    ).toBe(true);
  });
});
