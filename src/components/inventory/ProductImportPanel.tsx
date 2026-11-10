import {Input}from'@/components/ui/input';
import {DataTable}from'@/components/shared/DataTable';
import React, { useState } from 'react';
import { Upload, Download, CheckCircle2, AlertTriangle } from 'lucide-react';
import { productsService, stylesService } from '../../lib/services';
import { buildImportPlan, IMPORT_COLUMNS, IMPORT_TEMPLATE, ImportPlan } from '../../lib/csvImport';
import { swalConfig } from '../../lib/sweetAlert';
import { getErrorMessage } from '../../lib/errors';

interface StyleResult {
  code: string;
  ok: boolean;
  message?: string;
}

// Import products from a CSV file (e.g. exported from Excel).
// The whole file is checked first; nothing is imported while any row has an error.
export function ProductImportPanel({ template = IMPORT_TEMPLATE }: { template?: string } = {}) {
  const [fileName, setFileName] = useState('');
  const [plan, setPlan] = useState<ImportPlan | null>(null);
  const [checking, setChecking] = useState(false);
  const [importing, setImporting] = useState(false);
  const [results, setResults] = useState<StyleResult[]>([]);

  const downloadTemplate = (examples: boolean) => {
    const contents = examples ? template : IMPORT_COLUMNS.join(',') + '\n';
    const url = URL.createObjectURL(new Blob([contents], { type: 'text/csv' }));
    const a = document.createElement('a');
    a.href = url;
    a.download = examples ? 'product-import-examples.csv' : 'bicycles-products-blank.csv';
    a.click();
    URL.revokeObjectURL(url);
  };

  const handleFile = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file) return;
    if (file.size > 5_000_000) {
      swalConfig.error('Please use a file under 5 MB');
      return;
    }
    setFileName(file.name);
    setResults([]);
    setChecking(true);
    try {
      const [text, styleCodes, identifiers] = await Promise.all([file.text(), stylesService.listCodes(), productsService.identifiers()]);
      setPlan(buildImportPlan(text, {
        skus: new Set(identifiers.skus.map(sku => sku.toUpperCase())),
        barcodes: new Set(identifiers.barcodes.map(b => b.toUpperCase())),
        styleCodes: new Set(styleCodes.map(c => c.toUpperCase())),
      }));
    } catch (error) {
      swalConfig.error(`Could not read the file: ${getErrorMessage(error)}`);
      setPlan(null);
    } finally {
      setChecking(false);
    }
  };

  const handleImport = async () => {
    if (!plan || plan.errors.length > 0 || plan.styles.length === 0) return;
    const confirm = await swalConfig.confirm(
      'Import products?',
      `${plan.styles.length} styles with ${plan.rowCount} items will be added, including opening stock.`,
      'Import'
    );
    if (!confirm.isConfirmed) return;

    setImporting(true);
    const done: StyleResult[] = [];
    // One style per transaction: a failure only affects that style
    for (const style of plan.styles) {
      try {
        await stylesService.save(style);
        done.push({ code: style.code, ok: true });
      } catch (error) {
        done.push({ code: style.code, ok: false, message: getErrorMessage(error) });
      }
      setResults([...done]);
    }
    setImporting(false);
    setPlan(null);

    const failed = done.filter(r => !r.ok).length;
    if (failed === 0) swalConfig.success(`Imported ${done.length} styles`);
    else swalConfig.warning(`Imported ${done.length - failed} styles; ${failed} failed (see the list)`);
  };

  const totals = plan ? {
    items: plan.styles.reduce((n, s) => n + s.variants.length, 0),
    stock: plan.styles.reduce((n, s) => n + s.variants.reduce((m, v) => m + (v.openingStock ?? 0), 0), 0),
  } : null;

  return (
    <div className="space-y-6">
      <div className="card p-6 space-y-4">
        <div className="flex flex-col md:flex-row md:items-start justify-between gap-4">
          <div>
            <h2 className="text-lg font-bold text-link">Import products from a spreadsheet</h2>
            <p className="text-sm text-bodytext max-w-2xl">
              Save your sheet as CSV with one row per size/color. Rows with the same <code>style_code</code> become one
              style. Kinds: <code>item</code>, <code>pack</code>, <code>service</code>.
              The file is checked before anything is saved.
            </p>
            <p className="text-xs text-bodytext mt-2 font-mono break-all">{IMPORT_COLUMNS.join(', ')}</p>
          </div>
          <div className="flex flex-wrap gap-2">
            <button type="button" onClick={() => downloadTemplate(false)} className="btn btn-primary btn-md">
              <Download className="h-4 w-4" /><span>Download blank template</span>
            </button>
            <button type="button" onClick={() => downloadTemplate(true)} className="btn btn-secondary btn-md">
              <Download className="h-4 w-4" /><span>Download examples</span>
            </button>
          </div>
        </div>

        <p className="text-sm text-bodytext">Start with the blank template for your real products. Example prices and stock are for guidance only. Use size for the frame size (S, M, L) or wheel size for kids bikes, and fit for the variant such as 7-speed. Specifications such as brakes and gears are added per style after import. Add photos and publish each saved style from its Website tab.</p>
        <label className="flex items-center justify-center gap-3 border-2 border-dashed border-border rounded-xl p-8 cursor-pointer hover:border-primary">
          <Upload className="h-6 w-6 text-bodytext" />
          <span className="text-link">{checking ? 'Checking…' : fileName ? `Choose another file (${fileName})` : 'Choose a CSV file'}</span>
          <Input type="file" accept=".csv,text/csv" onChange={handleFile} className="hidden" disabled={checking || importing} />
        </label>

        {plan && plan.errors.length > 0 && (
          <div className="bg-lighterror border border-lighterror rounded-xl p-4">
            <p className="font-semibold text-error flex items-center gap-2">
              <AlertTriangle className="h-5 w-5" />
              {plan.errors.length} {plan.errors.length === 1 ? 'problem' : 'problems'} found. Fix the sheet and choose the file again.
            </p>
            <ul className="mt-2 text-sm text-error space-y-1 max-h-64 overflow-y-auto">
              {plan.errors.map((e, i) => <li key={i}>Line {e.row}: {e.message}</li>)}
            </ul>
          </div>
        )}

        {plan && plan.errors.length === 0 && totals && (
          <div className="space-y-4">
            <div className="bg-lightsuccess border border-lightsuccess rounded-xl p-4 flex flex-col md:flex-row md:items-center justify-between gap-3">
              <p className="text-success flex items-center gap-2">
                <CheckCircle2 className="h-5 w-5" />
                Ready: {plan.styles.length} styles, {totals.items} items, opening stock {totals.stock}.
              </p>
              <button type="button" onClick={handleImport} className="btn btn-primary btn-md" disabled={importing}>
                <Upload className="h-4 w-4" /><span>{importing ? 'Importing…' : 'Import'}</span>
              </button>
            </div>
            <div className="overflow-x-auto max-h-96">
              <DataTable className="table">
                <thead className="table-header">
                  <tr>
                    <th className="table-header-cell">Style</th>
                    <th className="table-header-cell">Kind</th>
                    <th className="table-header-cell">Items</th>
                    <th className="table-header-cell text-right">Opening stock</th>
                  </tr>
                </thead>
                <tbody className="bg-card divide-y divide-border">
                  {plan.styles.map(s => (
                    <tr key={s.code}>
                      <td className="table-cell">
                        <div className="font-medium">{s.name}</div>
                        <div className="text-xs text-bodytext font-mono">{s.code}</div>
                      </td>
                      <td className="table-cell">{s.kind}</td>
                      <td className="table-cell text-sm">
                        {s.variants.map(v => [v.size, v.color, v.fit].filter(Boolean).join(' ') || v.sku).join(', ')}
                      </td>
                      <td className="table-cell text-right">
                        {s.variants.reduce((n, v) => n + (v.openingStock ?? 0), 0)}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </DataTable>
            </div>
          </div>
        )}

        {results.length > 0 && (
          <div>
            <h3 className="font-semibold text-link mb-2">Import results</h3>
            <ul className="text-sm space-y-1">
              {results.map(r => (
                <li key={r.code} className={r.ok ? 'text-success' : 'text-error'}>
                  {r.ok ? '✓' : '✗'} {r.code}{r.message ? `: ${r.message}` : ''}
                </li>
              ))}
            </ul>
          </div>
        )}
      </div>
    </div>
  );
}
