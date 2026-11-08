import { describe, expect, it } from 'vitest';
import { buildImportPlan, IMPORT_TEMPLATE, parseCsv } from './csvImport';

const none = { skus: new Set<string>(), barcodes: new Set<string>(), styleCodes: new Set<string>() };
const header = 'style_code,style_name,kind,sku,size,color,price,cost,barcode,opening_stock';

describe('parseCsv', () => {
  it('handles quotes, escaped quotes, commas and CRLF', () => {
    expect(parseCsv('a,b\r\n"x, y","say ""hi"""\r\n')).toEqual([['a', 'b'], ['x, y', 'say "hi"']]);
  });

  it('skips blank lines and a byte order mark', () => {
    expect(parseCsv('\uFEFFa,b\n\n1,2\n')).toEqual([['a', 'b'], ['1', '2']]);
  });
});

describe('buildImportPlan', () => {
  it('groups rows into styles with their variants', () => {
    const plan = buildImportPlan(IMPORT_TEMPLATE, none);
    expect(plan.errors).toEqual([]);
    expect(plan.rowCount).toBe(4);
    expect(plan.styles.map(s => [s.code, s.variants.length])).toEqual([['LV-BRA-001', 2], ['LV-PAN-001', 1], ['LV-NGT-001', 1]]);
    expect(plan.styles[1].variants[0].openingStock).toBe(10);
  });

  it('reports every problem with its line number', () => {
    const csv = [
      header,
      'K1,Kurta,garment,K1-M,M,White,abc,,111,1',
      'K1,Kurta,garment,K1-M,L,White,100,,111,1.5',
      'K2,Shirt,jacket,K2-M,M,,100,,,',
    ].join('\n');
    const { errors } = buildImportPlan(csv, none);
    expect(errors).toEqual(expect.arrayContaining([
      { row: 2, message: 'price must be a number of 0 or more' },
      { row: 3, message: 'opening_stock must be a whole number' },
      { row: 3, message: 'SKU K1-M is also on line 2' },
      { row: 3, message: 'barcode 111 is also on line 2' },
      { row: 4, message: 'kind must be one of garment, pack, service' },
    ]));
  });

  it('refuses SKUs, barcodes and styles that already exist', () => {
    const existing = { skus: new Set(['K1-M']), barcodes: new Set(['111']), styleCodes: new Set(['K1']) };
    const { errors } = buildImportPlan(`${header}\nk1,Kurta,garment,k1-m,M,,100,,111,`, existing);
    expect(errors.map(e => e.message)).toEqual([
      'style K1 already exists (edit it in Inventory instead)',
      'SKU K1-M already exists',
      'barcode 111 already exists',
    ]);
  });

  it('refuses the same size and color twice in a style', () => {
    const { errors } = buildImportPlan(`${header}\nK1,Kurta,garment,A,M,Red,1,,,\nK1,Kurta,garment,B,m,red,1,,,`, none);
    expect(errors).toEqual([{ row: 3, message: 'same size and color as line 2' }]);
  });

  it('needs the required columns', () => {
    const { errors } = buildImportPlan('style_code,sku\nA,B', none);
    expect(errors.map(e => e.message)).toEqual(['Missing column "style_name"', 'Missing column "kind"', 'Missing column "price"']);
  });
});
