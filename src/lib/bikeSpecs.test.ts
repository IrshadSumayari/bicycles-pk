import { describe, expect, it } from 'vitest';
import { cleanSpecs, colourSwatch, groupedSpecs, primarySpecKeys, specRows, specSubtitle } from '../../shared/bicycles';

describe('spec helpers', () => {
  it('cleans values to known, trimmed, non-empty strings', () => {
    expect(cleanSpecs({ gears: ' 7 ', brakes: '', colour: 'Red', weight: 12, range: 'x'.repeat(130) }))
      .toEqual({ gears: '7', range: 'x'.repeat(120) });
    expect(cleanSpecs(null)).toEqual({});
    expect(cleanSpecs(['gears'])).toEqual({});
  });
  it('lists filled specs in display order', () => {
    expect(specRows({ weight: '14 kg', frame: 'Steel' }).map(r => r.label)).toEqual(['Frame', 'Weight']);
  });
  it('picks section-relevant fields first', () => {
    expect(primarySpecKeys('Balance Bikes')).toContain('age_range');
    expect(primarySpecKeys('City E-bikes')).toContain('battery');
    expect(primarySpecKeys(undefined)).toContain('frame');
  });
});

describe('product page spec helpers', () => {
  const specs = { frame: 'Aluminium', wheel_size: '27.5"', gears: '21-speed', warranty: '2 years', motor: ' ' };
  it('groups filled specs and drops empty groups', () => {
    const groups = groupedSpecs(specs);
    expect(groups.map((g) => g.title)).toEqual(['Frame and fork', 'Drivetrain', 'Wheels and brakes', 'Warranty']);
    expect(groups[0].rows).toEqual([{ key: 'frame', label: 'Frame', value: 'Aluminium' }]);
  });
  it('builds the subtitle from the section primary specs', () => {
    expect(specSubtitle(specs, 'Mountain Bikes')).toBe('Aluminium · 27.5" · 21-speed');
    expect(specSubtitle(null, 'Helmets')).toBe('');
  });
  it('maps colour names to swatches', () => {
    expect(colourSwatch('Matte Black')).toBe('#111111');
    expect(colourSwatch('Red/White')).toBe('#c8102e');
    expect(colourSwatch('Sunset')).toBe('#d0d0d0');
  });
});
