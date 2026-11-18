import {Input}from'@/components/ui/input';
import type { SettingsSectionProps } from './sectionTypes';

export function SalesTaxSection({
  value,
  onChange,
  admin,
}: SettingsSectionProps) {
  return (
    <section className="card p-5 space-y-4" aria-label="Sales and tax settings">
      <h2 className="font-bold text-xl">Sales &amp; tax</h2>
      <div className="grid md:grid-cols-2 gap-4">
        {(
          [
            ['taxRate', 'Tax (%)', 100, '0.001', 0],
            [
              'maxCashierDiscountPercent',
              'Cashier discount limit (%)',
              100,
              '0.01',
              10,
            ],
            ['returnWindowDays', 'Return window (days)', 365, '1', 7],
          ] as const
        ).map(([key, label, max, step, fallback]) => (
          <label className="block text-sm space-y-1" key={key}>
            {label}
            <Input
              className="input block"
              type="number"
              min="0"
              max={max}
              step={step}
              disabled={!admin}
              value={value[key] ?? fallback}
              onChange={(e) => onChange({ [key]: Number(e.target.value) })}
            />
          </label>
        ))}
        <label className="block text-sm space-y-1">
          Currency
          <Input className="input block" value="PKR" readOnly />
        </label>
        <label className="block text-sm space-y-1">
          Interface mode
          <select
            aria-label="Interface mode"
            className="select block"
            disabled={!admin}
            value={value.interfaceMode}
            onChange={(e) =>
              onChange({
                interfaceMode: e.target.value as typeof value.interfaceMode,
              })
            }
          >
            <option value="touch">Touch</option>
            <option value="traditional">Traditional</option>
          </select>
        </label>
      </div>
      <h3 className="font-semibold">Invoice preview</h3>
      <p className="text-sm text-bodytext">
        These fields control the legacy invoice preview. Issued invoice numbers
        are assigned automatically.
      </p>
      <div className="grid md:grid-cols-2 gap-4">
        <label className="block text-sm space-y-1">
          Invoice preview prefix
          <Input
            className="input block"
            maxLength={20}
            disabled={!admin}
            value={value.invoicePrefix}
            onChange={(e) => onChange({ invoicePrefix: e.target.value })}
          />
        </label>
        <label className="block text-sm space-y-1">
          Invoice preview counter
          <Input
            className="input block"
            type="number"
            min="0"
            step="1"
            disabled={!admin}
            value={value.invoiceCounter}
            onChange={(e) =>
              onChange({ invoiceCounter: Number(e.target.value) })
            }
          />
        </label>
      </div>
    </section>
  );
}
