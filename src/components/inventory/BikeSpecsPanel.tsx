import { useState } from 'react';
import { Input } from '@/components/ui/input';
import { primarySpecKeys, specFields, SPEC_MAX_LENGTH, type BikeSpecs, type SpecKey } from '../../../shared/bicycles';

// "At a glance" specifications shown on the website product page. Fields
// relevant to the category's section come first; the rest are optional.
export function BikeSpecsPanel({ category, value, onChange }: {
  category?: string;
  value: BikeSpecs;
  onChange: (specs: BikeSpecs) => void;
}) {
  const primary = primarySpecKeys(category);
  const others = specFields.filter(f => !primary.includes(f.key));
  const [showAll, setShowAll] = useState(() => others.some(f => value[f.key]));
  const set = (key: SpecKey, text: string) => {
    const next = { ...value };
    if (text) next[key] = text; else delete next[key];
    onChange(next);
  };
  const field = (key: SpecKey) => {
    const f = specFields.find(x => x.key === key)!;
    return (
      <label key={key} className="block">
        <span className="block text-sm font-medium text-link mb-1">{f.label}</span>
        <Input className="input" value={value[key] ?? ''} maxLength={SPEC_MAX_LENGTH}
               placeholder={f.hint} onChange={e => set(key, e.target.value)} />
      </label>
    );
  };
  return (
    <fieldset className="bg-lightgray rounded-xl p-4 space-y-3">
      <legend className="font-semibold text-link px-1">Specifications</legend>
      <p className="text-sm text-bodytext">Shown as “At a glance” on the website. Leave blank anything the supplier has not confirmed.</p>
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3">
        {primary.map(field)}
        {showAll && others.map(f => field(f.key))}
      </div>
      {!showAll && others.length > 0 && (
        <button type="button" className="btn btn-secondary btn-sm" onClick={() => setShowAll(true)}>More specifications</button>
      )}
    </fieldset>
  );
}
