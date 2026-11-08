export type ReportPreset =
  'today' | 'yesterday' | 'this_week' | 'this_month' | 'last_month' | 'custom';
export type ReportRange = { from: string; to: string };

// Match report_tz() in the database, regardless of the till's device timezone.
export function rangeFor(preset: ReportPreset, now: Date): ReportRange {
  if (Number.isNaN(now.getTime()))
    throw new Error('Choose a valid report date');
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Karachi',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(now);
  const part = (key: string) =>
    Number(parts.find((p) => p.type === key)?.value);
  const today = new Date(
    Date.UTC(part('year'), part('month') - 1, part('day')),
  );
  const from = new Date(today);
  const to = new Date(today);
  switch (preset) {
    case 'yesterday':
      from.setUTCDate(from.getUTCDate() - 1);
      to.setUTCDate(to.getUTCDate() - 1);
      break;
    case 'this_week':
      from.setUTCDate(from.getUTCDate() - ((from.getUTCDay() + 6) % 7));
      to.setTime(from.getTime());
      to.setUTCDate(to.getUTCDate() + 6);
      break;
    case 'this_month':
      from.setUTCDate(1);
      to.setUTCMonth(to.getUTCMonth() + 1, 0);
      break;
    case 'last_month':
      from.setUTCMonth(from.getUTCMonth() - 1, 1);
      to.setUTCDate(0);
      break;
    // Custom starts on today; the screen preserves the user's chosen dates.
    case 'custom':
    case 'today':
      break;
  }
  return {
    from: from.toISOString().slice(0, 10),
    to: to.toISOString().slice(0, 10),
  };
}
