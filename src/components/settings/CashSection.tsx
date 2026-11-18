import {Input}from'@/components/ui/input';
import type { SettingsSectionProps } from './sectionTypes';

export function CashSection({ value, onChange, admin }: SettingsSectionProps) {
  return (
    <section className="card p-5 space-y-4" aria-label="Cash settings">
      <h2 className="font-bold text-xl">Cash</h2>
      <label className="block text-sm space-y-1">
        Cash difference alert (PKR)
        <Input
          className="input block"
          disabled={!admin}
          type="number"
          min="0"
          step="0.01"
          value={value.cashVarianceAlert ?? 500}
          onChange={(e) =>
            onChange({ cashVarianceAlert: Number(e.target.value) })
          }
        />
      </label>
    </section>
  );
}
