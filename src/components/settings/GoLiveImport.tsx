import {Input}from'@/components/ui/input';
import {DataTable}from'@/components/shared/DataTable';
import { useMemo, useState } from 'react';
import { useApp } from '../../context/SupabaseAppContext';
import { goLiveService } from '../../lib/services';
import { getErrorMessage } from '../../lib/errors';
import { downloadCsv, toCsv } from '../../lib/csv';
import { BALANCE_COLUMNS, buildBalancePlan } from '../../lib/goLiveImport';

export function GoLiveImport() {
  const { state } = useApp();
  const admin = state.currentUser?.role === 'admin';
  if (!admin) return null;
  return (
    <section className="card p-5 space-y-5" aria-label="Go-live import">
      <h2 className="font-bold text-xl">Go-live import</h2>
      <p className="text-sm text-bodytext">
        Import existing customer debts once, before opening. Balances already
        owed do not enter today's cash. Check the preview against your records.
      </p>
      <BalanceImport />
    </section>
  );
}

function BalanceImport() {
  const { state } = useApp();
  const [text, setText] = useState('');
  // A stable per-file ID survives errors and retry clicks, including lost responses.
  const [requestId, setRequestId] = useState('');
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState('');
  const [failures, setFailures] = useState<string[]>([]);
  const [completed, setCompleted] = useState(false);
  const plan = useMemo(() => buildBalancePlan(text), [text]);
  const title = 'Customer balances';
  async function upload(file?: File) {
    if (!file) return;
    try {
      setText(await file.text());
      setResult('');
      setFailures([]);
      setCompleted(false);
      setRequestId(crypto.randomUUID());
    } catch (error) {
      setFailures([getErrorMessage(error)]);
    }
  }
  async function run() {
    if (busy || plan.errors.length || !plan.records.length) return;
    setBusy(true);
    setFailures([]);
    try {
      const saved = await goLiveService.balances(plan.records, requestId);
      setCompleted(true);
      setResult(
        `${saved.created_customers} customers created; ${saved.balances} balances imported; ${state.settings.currency} ${saved.total_amount.toFixed(2)}; ${saved.skipped.length} skipped.`,
      );
      setFailures(
        saved.skipped.map(
          (item) =>
            `CSV row ${item.row + 1} (${item.phone}): skipped — ${item.reason}`,
        ),
      );
    } catch (error) {
      setFailures([getErrorMessage(error)]);
    } finally {
      setBusy(false);
    }
  }
  return (
    <div className="border-t pt-4 space-y-3" role="group" aria-label={title}>
      <h3 className="text-lg font-semibold">{title}</h3>
      <button
        type="button"
        disabled={busy}
        className="btn btn-primary btn-md"
        onClick={() =>
          downloadCsv(
            'balances-template.csv',
            toCsv(
              [],
              BALANCE_COLUMNS.map((key) => ({ key, label: key })),
            ),
          )
        }
      >
        Download template CSV
      </button>
      <label className="block text-sm">
        Upload {title.toLowerCase()} CSV
        <Input
          type="file"
          accept=".csv,text/csv"
          disabled={busy}
          className="input block mt-1"
          onChange={(event) => void upload(event.target.files?.[0])}
        />
      </label>
      {text && (
        <>
          <p>
            {plan.preview.length} rows; {plan.records.length} balances;{' '}
            {plan.errors.length} errors.
          </p>
          <div className="overflow-x-auto max-h-80">
            <DataTable className="table w-full">
              <thead className="table-header">
                <tr>
                  <th className="table-cell">CSV row</th>
                  {Object.keys(plan.preview[0]?.cells ?? {}).map((key) => (
                    <th className="table-cell" key={key}>
                      {key}
                    </th>
                  ))}
                  <th className="table-cell">Errors</th>
                </tr>
              </thead>
              <tbody>
                {plan.preview.map((row) => {
                  const errors = plan.errors.filter(
                    (error) => error.row === row.row || error.row === 1,
                  );
                  return (
                    <tr
                      key={row.row}
                      className={errors.length ? 'bg-lighterror' : ''}
                    >
                      <td className="table-cell">{row.row}</td>
                      {Object.entries(row.cells).map(([key, value]) => (
                        <td className="table-cell" key={key}>
                          {value}
                        </td>
                      ))}
                      <td className="table-cell text-error">
                        {errors.map((error) => error.message).join('; ')}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </DataTable>
          </div>
          {plan.errors
            .filter((error) => error.row === 1)
            .map((error, i) => (
              <p role="alert" className="text-error" key={i}>
                {error.message}
              </p>
            ))}
          <button
            type="button"
            className="btn btn-primary btn-md"
            disabled={
              busy || !!plan.errors.length || !plan.records.length || completed
            }
            onClick={() => void run()}
          >
            {busy ? 'Importing…' : `Import ${title.toLowerCase()}`}
          </button>
        </>
      )}
      <div aria-live="polite">{result && <p>{result}</p>}</div>
      {!!failures.length && (
        <ul className="text-sm text-warning space-y-1">
          {failures.map((failure, i) => (
            <li key={i}>{failure}</li>
          ))}
        </ul>
      )}
    </div>
  );
}
