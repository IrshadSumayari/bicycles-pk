import type { SettingsSectionProps } from './sectionTypes';

export function ReceiptsSection({
  value,
  onChange,
  admin,
}: SettingsSectionProps) {
  return (
    <section className="card p-5 space-y-4" aria-label="Receipt settings">
      <h2 className="font-bold text-xl">Receipts</h2>
      <div className="grid md:grid-cols-2 gap-4">
        {(
          [
            ['receiptHeader', 'Receipt header'],
            ['receiptFooter', 'Receipt footer'],
          ] as const
        ).map(([key, label]) => (
          <label className="block text-sm space-y-1" key={key}>
            {label}
            <textarea
              aria-label={label}
              className="textarea block w-full"
              maxLength={500}
              rows={3}
              value={value[key] ?? ''}
              onChange={(e) => onChange({ [key]: e.target.value })}
            />
          </label>
        ))}
      </div>
      <label className="flex items-center gap-2 text-sm">
        <input
          type="checkbox"
          disabled={!admin}
          checked={value.receiptPrinter}
          onChange={(e) => onChange({ receiptPrinter: e.target.checked })}
        />
        Receipt printer enabled
      </label>
    </section>
  );
}
