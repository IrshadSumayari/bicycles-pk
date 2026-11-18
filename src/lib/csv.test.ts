import { describe, expect, it } from 'vitest';
import { toCsv } from './csv';

describe('CSV export', () => {
  const columns = [
    { key: 'name', label: 'Name' },
    { key: 'amount', label: 'Amount' },
  ];
  it('prefixes UTF-8 BOM and preserves Urdu text', () => {
    const csv = toCsv([{ name: 'کرتا', amount: 100 }], columns);
    expect(csv.charCodeAt(0)).toBe(0xfeff);
    expect(csv).toBe(String.fromCharCode(0xfeff) + 'Name,Amount\r\nکرتا,100');
    expect(Array.from(new TextEncoder().encode(csv).slice(0, 3))).toEqual([
      239, 187, 191,
    ]);
  });
  it('quotes commas, embedded quotes, and every newline form', () => {
    expect(
      toCsv(
        [
          { name: 'Helmet, white', amount: 1 },
          { name: 'Size "L"', amount: 2 },
          { name: 'one\ntwo', amount: 3 },
          { name: 'one\r\ntwo', amount: 4 },
          { name: 'one\rtwo', amount: 5 },
        ],
        columns,
      ),
    ).toBe(
      String.fromCharCode(0xfeff) +
        'Name,Amount\r\n"Helmet, white",1\r\n"Size ""L""",2\r\n"one\ntwo",3\r\n"one\r\ntwo",4\r\n"one\rtwo",5',
    );
  });
  it('quotes headers too', () => {
    expect(toCsv([], [{ key: 'x', label: 'Sold, "net"' }])).toBe(
      String.fromCharCode(0xfeff) + '"Sold, ""net"""',
    );
  });
  it('exports only requested columns in their visible order', () => {
    expect(
      toCsv(
        [{ hidden: 'secret', amount: -12.5, name: 'Cotton' }],
        [...columns].reverse(),
      ),
    ).toBe(String.fromCharCode(0xfeff) + 'Amount,Name\r\n-12.5,Cotton');
  });
  it('retains zero and renders null and missing fields as empty', () => {
    expect(toCsv([{ name: null, amount: 0 }, { name: '' }], columns)).toBe(
      String.fromCharCode(0xfeff) + 'Name,Amount\r\n,0\r\n,',
    );
  });
});
