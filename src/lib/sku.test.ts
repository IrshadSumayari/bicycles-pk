import { describe, expect, it } from 'vitest';
import { buildSku } from './sku';

describe('buildSku', () => {
  it('joins style code, color, size and fit', () => {
    expect(buildSku('sk-001', 'L', 'Navy', 'Slim')).toBe('SK-001-NAVY-L-SLIM');
  });

  it('shortens long colors and drops spaces and symbols', () => {
    expect(buildSku('SK-001', 'XL', 'Off White')).toBe('SK-001-OFFW-XL');
    expect(buildSku('TR-9', '32x30', 'Black')).toBe('TR-9-BLAC-32X3');
  });

  it('skips missing parts', () => {
    expect(buildSku('LAWN-1', undefined, 'Blue')).toBe('LAWN-1-BLUE');
    expect(buildSku('SVC')).toBe('SVC');
  });
});

describe('buildSku for bra + panty sets', () => {
  it('keeps both the bra and the panty size', () => {
    expect(buildSku('LV-SET', '34DD / XL', 'Rose')).toBe('LV-SET-ROSE-34DDXL');
    expect(buildSku('LV-SET', '34B / M')).toBe('LV-SET-34BM');
  });
});
