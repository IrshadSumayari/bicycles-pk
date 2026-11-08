export function scannerCode(
  value: string,
  key: string,
  composing = false,
): string | null {
  return key === 'Enter' && !composing && value.trim() ? value.trim() : null;
}
