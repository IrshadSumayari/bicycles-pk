import {DataTable}from'@/components/shared/DataTable';
import { Download } from 'lucide-react';
import { downloadCsv, toCsv, type CsvValue } from '../../lib/csv';

export type ReportColumn<T> = {
  key: keyof T & string;
  label: string;
  format?: (value: T[keyof T & string]) => string;
};

export function ReportTable<T extends Record<string, CsvValue>>({
  title,
  filename,
  rows,
  columns,
  onSelect,
}: {
  title: string;
  filename: string;
  rows: T[];
  columns: ReportColumn<T>[];
  onSelect?: (row: T) => void;
}) {
  // One display representation drives both the table and its CSV export.
  const visibleRows = rows.map((row) =>
    Object.fromEntries(
      columns.map((column) => [
        column.key,
        column.format
          ? column.format(row[column.key])
          : String(row[column.key] ?? '—'),
      ]),
    ),
  );
  return (
    <section className="card overflow-hidden" aria-label={title}>
      <div className="flex flex-wrap items-center justify-between gap-3 p-4 border-b border-border">
        <h2 className="font-semibold text-link">{title}</h2>
        <button
          type="button"
          className="btn btn-primary btn-md"
          disabled={rows.length === 0}
          onClick={() => downloadCsv(filename, toCsv(visibleRows, columns))}
        >
          <Download className="h-4 w-4" aria-hidden="true" />
          Export CSV
        </button>
      </div>
      <div className="overflow-x-auto">
        <DataTable className="table">
          <thead className="table-header">
            <tr>
              {columns.map((column) => (
                <th key={column.key} scope="col" className="table-header-cell">
                  {column.label}
                </th>
              ))}
            </tr>
          </thead>
          <tbody className="bg-card divide-y divide-border">
            {rows.length === 0 && (
              <tr>
                <td
                  colSpan={columns.length}
                  className="table-cell text-center text-bodytext"
                >
                  No activity for this period.
                </td>
              </tr>
            )}
            {visibleRows.map((row, index) => (
              <tr key={index} className="table-row">
                {columns.map((column, columnIndex) => (
                  <td key={column.key} className="table-cell">
                    {onSelect && columnIndex === 0 ? (
                      <button
                        type="button"
                        className="font-medium text-primary underline underline-offset-2"
                        onClick={() => onSelect(rows[index])}
                      >
                        {row[column.key]}
                      </button>
                    ) : (
                      row[column.key]
                    )}
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </DataTable>
      </div>
    </section>
  );
}
