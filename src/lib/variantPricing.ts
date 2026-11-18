export function applyVariantAmount<T extends { price: number; cost?: number }>(
  rows: T[], field: 'price' | 'cost', input: string,
): T[] {
  const value = Number(input);
  if (!input.trim() || !Number.isFinite(value) || value < 0) {
    throw new Error('Enter a valid amount of zero or more.');
  }
  return rows.map(row => ({ ...row, [field]: value }));
}
