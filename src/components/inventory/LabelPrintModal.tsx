import { useProductSearch } from '../../lib/hooks/useProducts';
import { ReportStatus } from '../reports/ReportStatus';
import { useEffect, useMemo, useRef, useState } from 'react';
import { X, Printer, Trash2 } from 'lucide-react';
import JsBarcode from 'jsbarcode';
import { Product, productLabel } from '../../types';
import { useApp } from '../../context/SupabaseAppContext';

interface LabelPrintModalProps {
  isOpen: boolean;
  onClose: () => void;
  initial?: Product[];
}

type Layout = 'roll' | 'a4';

const LAYOUTS: Record<Layout, { label: string; css: string }> = {
  // Thermal label printer, one 50 x 30 mm label per page
  roll: {
    label: 'Label printer (50 × 30 mm)',
    css: `@page { size: 50mm 30mm; margin: 0; }
      .sheet { display: block; }
      .label { width: 50mm; height: 30mm; page-break-after: always; break-after: page; }`,
  },
  // Plain A4 sticker sheet, 3 x 8 labels (70 x 37 mm)
  a4: {
    label: 'A4 sticker sheet (3 × 8)',
    css: `@page { size: A4; margin: 8mm 0 0 0; }
      .sheet { display: grid; grid-template-columns: repeat(3, 70mm); grid-auto-rows: 37mm; }
      .label { width: 70mm; height: 37mm; }`,
  },
};

interface Line {
  product: Product;
  copies: number;
}

// Code 128 price tags: store name, item, size / color, price and barcode.
// Items without a barcode use their SKU, which the POS search also finds.
export function LabelPrintModal({ isOpen, onClose, initial = [] }: LabelPrintModalProps) {
  const { state } = useApp();
  const [lines, setLines] = useState<Line[]>([]);
  const [search, setSearch] = useState('');
  const [layout, setLayout] = useState<Layout>('roll');
  const [showPrice, setShowPrice] = useState(true);
  const previewRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (isOpen) {
      setLines(initial.map(product => ({ product, copies: Math.max(1, Math.round(product.stock)) })));
      setSearch('');
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isOpen]);

  const query = useProductSearch({ q: search, limit: 20 }, isOpen && !!search.trim());
  const matches = search.trim() ? (query.data?.rows ?? []).filter(p => p.kind !== 'service') : [];

  const labels = useMemo(() => lines.flatMap(l => Array.from({ length: l.copies }, () => l.product)), [lines]);

  // Draw a small preview of the first label
  useEffect(() => {
    if (!previewRef.current || lines.length === 0) return;
    const svg = previewRef.current.querySelector('svg');
    if (svg) drawBarcode(svg, codeFor(lines[0].product));
  }, [lines]);

  if (!isOpen) return null;

  const add = (product: Product) => {
    setLines(prev => (prev.some(l => l.product.id === product.id) ? prev : [...prev, { product, copies: 1 }]));
    setSearch('');
  };

  const print = () => {
    if (labels.length === 0) return;
    const win = window.open('', '_blank', 'width=600,height=800');
    if (!win) return;
    const doc = win.document;
    doc.title = 'Labels';
    const style = doc.createElement('style');
    style.textContent = `
      * { box-sizing: border-box; }
      body { margin: 0; font-family: Arial, Helvetica, sans-serif; color: #000; }
      ${LAYOUTS[layout].css}
      .label { padding: 1.5mm 2mm; overflow: hidden; display: flex; flex-direction: column; justify-content: space-between; }
      .store { font-size: 6pt; text-transform: uppercase; letter-spacing: 0.5pt; }
      .name { font-size: 7.5pt; font-weight: bold; line-height: 1.1; max-height: 2.2em; overflow: hidden; }
      .meta { display: flex; justify-content: space-between; align-items: baseline; font-size: 7pt; }
      .price { font-size: 10pt; font-weight: bold; }
      svg { width: 100%; height: 11mm; display: block; }
    `;
    doc.head.appendChild(style);
    const sheet = doc.createElement('div');
    sheet.className = 'sheet';
    labels.forEach(product => sheet.appendChild(buildLabel(doc, product, state.settings.storeName, state.settings.currency, showPrice)));
    doc.body.appendChild(sheet);
    win.focus();
    // Give the browser a moment to lay out the barcodes before printing
    win.setTimeout(() => { win.print(); win.close(); }, 250);
  };

  const first = lines[0]?.product;

  return (
    <div className="modal-overlay">
      <div className="modal max-w-3xl">
        <div className="modal-header">
          <h2 className="text-xl font-bold text-link">Print labels</h2>
          <button onClick={onClose} className="text-bodytext hover:text-bodytext p-2 rounded-xl hover:bg-lightgray">
            <X className="h-6 w-6" />
          </button>
        </div>
        <div className="modal-body space-y-4">
          <div className="relative">
            <input value={search} onChange={e => setSearch(e.target.value)} className="input" placeholder="Search items to add" />
            <ReportStatus loading={query.isFetching} error={query.error} retry={() => void query.refetch()} />
            {matches.length > 0 && (
              <div className="absolute z-10 mt-1 w-full bg-card border border-border rounded-xl shadow-lg max-h-64 overflow-y-auto">
                {matches.map(p => (
                  <button key={p.id} type="button" onClick={() => add(p)}
                          className="w-full text-left px-4 py-2 hover:bg-lightgray flex justify-between">
                    <span>{productLabel(p)}</span>
                    <span className="text-sm text-bodytext font-mono">{p.sku}</span>
                  </button>
                ))}
              </div>
            )}
          </div>

          <table className="table">
            <thead className="table-header">
              <tr>
                <th className="table-header-cell">Item</th>
                <th className="table-header-cell">Code</th>
                <th className="table-header-cell">Copies</th>
                <th className="table-header-cell" />
              </tr>
            </thead>
            <tbody className="bg-card divide-y divide-border">
              {lines.length === 0 && (
                <tr><td colSpan={4} className="table-cell text-center text-bodytext py-6">Add items to print</td></tr>
              )}
              {lines.map(l => (
                <tr key={l.product.id}>
                  <td className="table-cell">{productLabel(l.product)}</td>
                  <td className="table-cell font-mono text-sm">{codeFor(l.product)}</td>
                  <td className="table-cell">
                    <input type="number" min="1" max="500" value={l.copies}
                           onChange={e => setLines(prev => prev.map(x => x.product.id === l.product.id
                             ? { ...x, copies: Math.min(500, Math.max(1, Math.floor(Number(e.target.value) || 1))) } : x))}
                           className="input w-20" />
                  </td>
                  <td className="table-cell">
                    <button type="button" onClick={() => setLines(prev => prev.filter(x => x.product.id !== l.product.id))}
                            className="text-error hover:text-error p-1">
                      <Trash2 className="h-4 w-4" />
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>

          <div className="flex flex-wrap items-center gap-6">
            <label className="flex items-center gap-2">
              <span className="text-sm font-medium text-link">Paper</span>
              <select value={layout} onChange={e => setLayout(e.target.value as Layout)} className="select w-64">
                {(Object.keys(LAYOUTS) as Layout[]).map(k => <option key={k} value={k}>{LAYOUTS[k].label}</option>)}
              </select>
            </label>
            <label className="flex items-center gap-2">
              <input type="checkbox" checked={showPrice} onChange={e => setShowPrice(e.target.checked)} />
              <span className="text-sm text-link">Show price</span>
            </label>
          </div>

          {first && (
            <div>
              <p className="text-sm text-bodytext mb-2">Preview</p>
              <div ref={previewRef} className="border border-border rounded p-2 w-64 space-y-1 bg-card">
                <div className="text-[10px] uppercase tracking-wide text-bodytext">{state.settings.storeName}</div>
                <div className="text-xs font-bold leading-tight">{productLabel(first)}</div>
                <svg className="w-full h-12" />
                <div className="flex justify-between text-xs">
                  <span>{first.sku}</span>
                  {showPrice && <span className="font-bold">{priceText(first, state.settings.currency)}</span>}
                </div>
              </div>
            </div>
          )}
        </div>
        <div className="modal-footer">
          <span className="text-sm text-bodytext mr-auto">{labels.length} labels</span>
          <button type="button" onClick={onClose} className="btn btn-secondary btn-md">Close</button>
          <button type="button" onClick={print} className="btn btn-primary btn-md" disabled={labels.length === 0}>
            <Printer className="h-4 w-4" /><span>Print</span>
          </button>
        </div>
      </div>
    </div>
  );
}

function codeFor(product: Product): string {
  return product.barcode || product.sku;
}

function priceText(product: Product, currency: string): string {
  return `${currency} ${product.price.toFixed(0)}`;
}

function drawBarcode(svg: SVGSVGElement, code: string) {
  try {
    JsBarcode(svg, code, { format: 'CODE128', displayValue: true, fontSize: 12, height: 40, margin: 0, width: 1.4 });
  } catch {
    svg.innerHTML = '';
  }
}

function buildLabel(doc: Document, product: Product, store: string, currency: string, showPrice: boolean): HTMLElement {
  const label = doc.createElement('div');
  label.className = 'label';

  const storeEl = doc.createElement('div');
  storeEl.className = 'store';
  storeEl.textContent = store;

  const name = doc.createElement('div');
  name.className = 'name';
  name.textContent = productLabel(product);

  const svg = doc.createElementNS('http://www.w3.org/2000/svg', 'svg');
  drawBarcode(svg, codeFor(product));

  const meta = doc.createElement('div');
  meta.className = 'meta';
  const sku = doc.createElement('span');
  sku.textContent = [product.size, product.color].filter(Boolean).join(' / ') || product.sku;
  meta.appendChild(sku);
  if (showPrice) {
    const price = doc.createElement('span');
    price.className = 'price';
    price.textContent = priceText(product, currency);
    meta.appendChild(price);
  }

  label.append(storeEl, name, svg, meta);
  return label;
}
