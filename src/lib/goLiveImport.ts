import { parseCsv, type ImportRowError } from './csvImport';
export const BALANCE_COLUMNS = ['name', 'phone', 'amount', 'note'];
export type OpeningBalance = {
  name: string;
  phone: string;
  amount: number;
  note: string;
};
export type ImportPreview = { row: number; cells: Record<string, string> };
export type GoLivePlan<T> = {
  records: T[];
  preview: ImportPreview[];
  errors: ImportRowError[];
};

export function importPhone(value: string): string | null {
  const digits = value.replace(/\D/g, '');
  const phone = digits.startsWith('00')
    ? '+' + digits.slice(2)
    : /^0\d{10}$/.test(digits)
      ? '+92' + digits.slice(1)
      : /^92\d{10}$/.test(digits)
        ? '+' + digits
        : /^3\d{9}$/.test(digits)
          ? '+92' + digits
          : value.trim().startsWith('+')
            ? '+' + digits
            : digits;
  return /^\+[1-9]\d{7,14}$/.test(phone) ? phone : null;
}
function money(value: string, positive = false): boolean {
  return (
    /^\d{1,12}(\.\d{1,2})?$/.test(value) &&
    Number(value) < 1e12 &&
    (positive ? Number(value) > 0 : true)
  );
}
function readFile(text: string, columns: string[]) {
  const rows = parseCsv(text);
  const header = rows[0]?.map((cell) => cell.trim().toLowerCase()) ?? [];
  const errors: ImportRowError[] = [];
  // parseCsv handles quoted newlines and escapes. Refuse an unfinished quoted
  // field rather than silently importing a truncated paper note.
  if ((text.match(/"/g)?.length ?? 0) % 2 !== 0)
    errors.push({ row: 1, message: 'A quoted CSV field is not closed' });
  if (rows.length < 2)
    errors.push({ row: 1, message: 'The file has no data rows' });
  for (const column of columns)
    if (!header.includes(column))
      errors.push({ row: 1, message: `Missing column "${column}"` });
  if (new Set(header).size !== header.length)
    errors.push({ row: 1, message: 'Column names must be unique' });
  const preview = rows.slice(1).map((cells, index) => {
    if (cells.length !== header.length)
      errors.push({
        row: index + 2,
        message: 'Number of cells does not match the header',
      });
    return {
      row: index + 2,
      cells: Object.fromEntries(
        header.map((name, i) => [name, (cells[i] ?? '').trim()]),
      ),
    };
  });
  return { preview, errors };
}

export function buildBalancePlan(text: string): GoLivePlan<OpeningBalance> {
  const { preview, errors } = readFile(text, BALANCE_COLUMNS);
  const records = preview.map(({ row, cells: c }) => {
    const fail = (message: string) => errors.push({ row, message });
    if (!c.name) fail('Name is required');
    if (!importPhone(c.phone ?? '')) fail('Phone number is not valid');
    if (!money(c.amount ?? '', true))
      fail('Amount must be positive with at most 2 decimals');
    return {
      name: c.name,
      phone: c.phone,
      amount: Number(c.amount),
      note: c.note,
    };
  });
  return { records, preview, errors };
}
