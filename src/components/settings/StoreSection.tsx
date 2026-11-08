import {Input}from'@/components/ui/input';
import type { SettingsSectionProps } from './sectionTypes';
import { LogoUpload } from './LogoUpload';

export function StoreSection({ value, onChange, admin }: SettingsSectionProps) {
  return (
    <section className="card p-5 space-y-4" aria-label="Store settings">
      <h2 className="font-bold text-xl">Store</h2>
      <div className="grid md:grid-cols-2 gap-4">
        {(
          [
            ['storeName', 'Store name'],
            ['storeAddress', 'Address'],
            ['storePhone', 'Phone'],
            ['storeEmail', 'Email'],
            ['ntn', 'NTN'],
            ['strn', 'STRN'],
          ] as const
        ).map(([key, label]) => (
          <label className="block text-sm space-y-1" key={key}>
            {label}
            <Input
              className="input block"
              disabled={!admin}
              value={value[key] ?? ''}
              onChange={(e) => onChange({ [key]: e.target.value })}
            />
          </label>
        ))}
      </div>
      <LogoUpload
        currentLogo={value.storeLogo}
        disabled={!admin}
        onLogoChange={(storeLogo) => onChange({ storeLogo })}
      />
    </section>
  );
}
