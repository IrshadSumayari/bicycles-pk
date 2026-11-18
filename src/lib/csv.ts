export type CsvValue = string | number | null;
export type CsvColumn = { key: string; label: string };

export function toCsv(
  rows: readonly Record<string, CsvValue>[],
  columns: readonly CsvColumn[],
): string {
  const quote = (value: CsvValue | undefined) => {
    const text = value == null ? '' : String(value);
    return /[",\r\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
  };
  return (
    String.fromCharCode(0xfeff) +
    [
      columns.map((column) => quote(column.label)).join(','),
      ...rows.map((row) =>
        columns.map((column) => quote(row[column.key])).join(','),
      ),
    ].join('\r\n')
  );
}

export function downloadCsv(filename: string, csv: string): void {
  const url = URL.createObjectURL(
    new Blob([csv], { type: 'text/csv;charset=utf-8;' }),
  );
  const link = document.createElement('a');
  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  link.remove();
  // Let the browser start reading the Blob before releasing it.
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
