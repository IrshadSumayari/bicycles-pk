// Built-in reasons, so stock can be adjusted before any are added in Settings.
// Other is always last and needs a note.
export const DEFAULT_REASONS = ['New stock received', 'Stock count correction', 'Damaged', 'Lost or stolen', 'Returned to supplier'];
export function stockReasons(custom: string[] = []): string[] {
  return [...new Set([...custom, ...DEFAULT_REASONS].filter(r => r.trim() && r.toLowerCase() !== 'other')), 'Other'];
}
