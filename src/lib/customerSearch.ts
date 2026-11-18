// Match local and international Pakistani numbers against the stored +92 format.
export function customerSearchTerm(value: string): string {
  const term = value.trim();
  if (!/^[+\d\s().-]+$/.test(term)) return term;
  const digits = term.replace(/\D/g, '');
  if (digits.startsWith('0092')) return `+${digits.slice(2)}`;
  if (digits.startsWith('92')) return `+${digits}`;
  if (digits.startsWith('0')) return `+92${digits.slice(1)}`;
  return digits;
}

// Quote PostgREST filter values and escape LIKE wildcards, so typed punctuation
// remains search text rather than changing the filter expression.
export function customerSearchFilter(value: string): string {
  const pattern = (term: string) => {
    const literal = term.replace(/[\\%_]/g, '\\$&');
    return `"%${literal.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}%"`;
  };
  return `name.ilike.${pattern(value.trim())},phone.ilike.${pattern(customerSearchTerm(value))},email.ilike.${pattern(value.trim())}`;
}
