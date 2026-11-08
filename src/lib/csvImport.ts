import { ProductKind } from '../types';
import type { StyleInput } from './services';

// Columns of the product import file. One row per sellable item (variant);
// rows with the same style_code become one style.
export const IMPORT_COLUMNS = [
  'style_code', 'style_name', 'kind', 'category', 'brand', 'material', 'season',
  'sku', 'size', 'color', 'fit', 'price', 'cost', 'barcode', 'opening_stock', 'min_stock',
] as const;

export const IMPORT_TEMPLATE = [
  IMPORT_COLUMNS.join(','),
  'LV-BRA-001,Everyday Lace Bra,garment,Bras,LadyVogue,Lace,Everyday,LV-BRA-001-ROSE-34B,34B,Rose,,2500,1200,,4,1',
  'LV-BRA-001,Everyday Lace Bra,garment,Bras,LadyVogue,Lace,Everyday,LV-BRA-001-ROSE-36B,36B,Rose,,2500,1200,,3,1',
  'LV-PAN-001,Cotton Briefs,garment,Panties,LadyVogue,Cotton,Everyday,LV-PAN-001-IVOR-M,M,Ivory,,800,350,,10,2',
  'LV-NGT-001,Satin Night Suit,garment,Nightwear,LadyVogue,Satin,Everyday,LV-NGT-001-ROSE-L,L,Rose,,4500,2200,,5,1',
].join('\n') + '\n';

export const JEWELLERY_IMPORT_TEMPLATE = [
  IMPORT_COLUMNS.join(','),
  'LV-EAR-001,Everyday Hoop Earrings,garment,Earrings,LadyVogue,Stainless steel,Everyday,LV-EAR-001-GOLD,One size,Gold tone,,1800,700,,5,1',
  'LV-RNG-001,Stacking Ring,garment,Rings,LadyVogue,Alloy,Everyday,LV-RNG-001-SILV-US7,US 7,Silver tone,,1200,400,,3,1',
  'LV-RNG-001,Stacking Ring,garment,Rings,LadyVogue,Alloy,Everyday,LV-RNG-001-SILV-US8,US 8,Silver tone,,1200,400,,2,1',
].join('\n') + '\n';

export const BAGS_IMPORT_TEMPLATE = [
  IMPORT_COLUMNS.join(','),
  'LV-TOT-001,Everyday Tote Bag,garment,Tote Bags,LadyVogue,Faux leather,Everyday,LV-TOT-001-BLAC-L,Large,Black,,6500,3000,,4,1',
  'LV-TOT-001,Everyday Tote Bag,garment,Tote Bags,LadyVogue,Faux leather,Everyday,LV-TOT-001-TAN-L,Large,Tan,,6500,3000,,3,1',
  'LV-CRS-001,Quilted Crossbody Bag,garment,Crossbody Bags,LadyVogue,Faux leather,Everyday,LV-CRS-001-IVOR-S,Small,Ivory,Chain strap,4800,2100,,5,1',
  'LV-WAL-001,Zip-Around Wallet,garment,Wallets & Purses,LadyVogue,Faux leather,Everyday,LV-WAL-001-MARO-OS,One size,Maroon,,2200,900,,6,2',
].join('\n') + '\n';

const KINDS: ProductKind[] = ['garment', 'pack', 'service'];

// RFC 4180 style parser: commas, double quotes, "" escapes, CRLF or LF
export function parseCsv(text: string): string[][] {
  const rows: string[][] = [];
  let row: string[] = [];
  let field = '';
  let quoted = false;
  const input = text.replace(/^\uFEFF/, '');

  for (let i = 0; i < input.length; i++) {
    const ch = input[i];
    if (quoted) {
      if (ch === '"') {
        if (input[i + 1] === '"') { field += '"'; i++; }
        else quoted = false;
      } else {
        field += ch;
      }
    } else if (ch === '"') {
      quoted = true;
    } else if (ch === ',') {
      row.push(field); field = '';
    } else if (ch === '\n' || ch === '\r') {
      if (ch === '\r' && input[i + 1] === '\n') i++;
      row.push(field); field = '';
      rows.push(row); row = [];
    } else {
      field += ch;
    }
  }
  if (field !== '' || row.length > 0) {
    row.push(field);
    rows.push(row);
  }
  return rows.filter(r => r.some(cell => cell.trim() !== ''));
}

export interface ImportRowError {
  row: number; // 1-based line in the file, header is line 1
  message: string;
}

export interface ImportPlan {
  styles: StyleInput[];
  errors: ImportRowError[];
  rowCount: number;
}

interface Existing {
  skus: Set<string>;
  barcodes: Set<string>;
  styleCodes: Set<string>;
}

// Validates the file and groups rows into styles ready for save_style().
// Nothing is imported while any row has an error.
export function buildImportPlan(text: string, existing: Existing): ImportPlan {
  const rows = parseCsv(text);
  const errors: ImportRowError[] = [];
  if (rows.length === 0) return { styles: [], errors: [{ row: 1, message: 'The file is empty' }], rowCount: 0 };

  const header = rows[0].map(h => h.trim().toLowerCase());
  const col = (name: string) => header.indexOf(name);
  for (const required of ['style_code', 'style_name', 'kind', 'sku', 'price']) {
    if (col(required) < 0) errors.push({ row: 1, message: `Missing column "${required}"` });
  }
  if (errors.length) return { styles: [], errors, rowCount: rows.length - 1 };

  const get = (r: string[], name: string) => (col(name) >= 0 ? (r[col(name)] ?? '').trim() : '');
  const num = (value: string) => (value === '' ? undefined : Number(value.replace(/,/g, '')));

  const styles = new Map<string, StyleInput>();
  const seenSkus = new Map<string, number>();
  const seenBarcodes = new Map<string, number>();
  const seenOptions = new Map<string, number>();

  rows.slice(1).forEach((r, index) => {
    const line = index + 2;
    const fail = (message: string) => errors.push({ row: line, message });

    const code = get(r, 'style_code').toUpperCase();
    const name = get(r, 'style_name');
    const kind = get(r, 'kind').toLowerCase() as ProductKind;
    const sku = get(r, 'sku').toUpperCase();
    const barcode = get(r, 'barcode');
    const price = num(get(r, 'price'));
    const cost = num(get(r, 'cost'));
    const opening = num(get(r, 'opening_stock'));
    const minStock = num(get(r, 'min_stock'));

    if (!code) fail('style_code is empty');
    if (!name) fail('style_name is empty');
    if (!KINDS.includes(kind)) fail(`kind must be one of ${KINDS.join(', ')}`);
    if (!sku) fail('sku is empty');
    if (price === undefined || !Number.isFinite(price) || price < 0) fail('price must be a number of 0 or more');
    if (cost !== undefined && (!Number.isFinite(cost) || cost < 0)) fail('cost must be a number of 0 or more');
    if (minStock !== undefined && (!Number.isFinite(minStock) || minStock < 0)) fail('min_stock must be 0 or more');
    if (opening !== undefined) {
      if (!Number.isFinite(opening) || opening < 0) fail('opening_stock must be 0 or more');
      else if (!Number.isInteger(opening)) fail('opening_stock must be a whole number');
      if (kind === 'service' && opening > 0) fail('services have no stock');
    }

    if (code && existing.styleCodes.has(code)) fail(`style ${code} already exists (edit it in Inventory instead)`);
    if (sku) {
      if (existing.skus.has(sku)) fail(`SKU ${sku} already exists`);
      if (seenSkus.has(sku)) fail(`SKU ${sku} is also on line ${seenSkus.get(sku)}`);
      else seenSkus.set(sku, line);
    }
    if (barcode) {
      if (existing.barcodes.has(barcode.toUpperCase())) fail(`barcode ${barcode} already exists`);
      if (seenBarcodes.has(barcode)) fail(`barcode ${barcode} is also on line ${seenBarcodes.get(barcode)}`);
      else seenBarcodes.set(barcode, line);
    }

    const optionKey = [code, get(r, 'size'), get(r, 'color'), get(r, 'fit')].join('|').toLowerCase();
    if (code && seenOptions.has(optionKey)) fail(`same size and color as line ${seenOptions.get(optionKey)}`);
    else seenOptions.set(optionKey, line);

    let style = styles.get(code);
    if (code && !style) {
      style = {
        kind,
        code,
        name,
        category: get(r, 'category') || undefined,
        brand: get(r, 'brand') || undefined,
        material: get(r, 'material') || undefined,
        season: get(r, 'season') || undefined,
        taxable: true,
        active: true,
        trackInventory: kind !== 'service',
        variants: [],
      };
      styles.set(code, style);
    } else if (style && (style.kind !== kind || style.name !== name)) {
      fail(`style ${code} has a different name or kind on an earlier line`);
    }

    style?.variants.push({
      sku,
      size: get(r, 'size') || undefined,
      color: get(r, 'color') || undefined,
      fit: get(r, 'fit') || undefined,
      price: price ?? 0,
      cost,
      barcode: barcode || undefined,
      minStock,
      active: true,
      openingStock: opening,
    });
  });

  return { styles: [...styles.values()], errors, rowCount: rows.length - 1 };
}
