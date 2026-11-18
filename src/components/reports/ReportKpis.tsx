import { StatCard, type StatTone } from '@/components/shared/StatCard';

// Cycle accent colours so neighbouring KPI cards are easy to tell apart.
const TONES: StatTone[] = ['primary', 'success', 'secondary', 'warning', 'info'];

export function ReportKpis({
  items,
}: {
  items: { label: string; value: string }[];
}) {
  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-5 gap-4">
      {items.map((item, index) => (
        <StatCard key={item.label} label={item.label} value={item.value} tone={TONES[index % TONES.length]} />
      ))}
    </div>
  );
}
