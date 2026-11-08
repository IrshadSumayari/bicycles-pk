import { describe, expect, it } from 'vitest';
import {
  colorHex,
  hasModelPhotos,
  isGarmentMaterial,
  readTryOn,
  spinFor,
  tonesFor,
  tryOnError,
} from '../../shared/tryOn';

const style = '00000000-0000-0000-0000-00000000aaaa';
const other = '00000000-0000-0000-0000-00000000bbbb';
const id = '11111111-2222-3333-4444-555555555555';
const frames = (n: number, owner = style) =>
  Array.from({ length: n }, () => `styles/${owner}/spin/${id}.webp`);

describe('try-on data', () => {
  it('accepts a 3D model, colours and model photos for the same style', () => {
    expect(
      tryOnError(
        {
          model_path: `styles/${style}/${id}.glb`,
          garment_materials: ['Lace'],
          colors: { Rose: '#c98a9b' },
          models: { fair: { Rose: frames(24) }, dusky: { Rose: frames(4) } },
        },
        style,
      ),
    ).toBeNull();
    expect(tryOnError({}, style)).toBeNull();
  });
  it("rejects another style's files, unknown tones and keys, and bad shades", () => {
    expect(tryOnError({ model_path: `styles/${other}/${id}.glb` }, style)).not.toBeNull();
    expect(tryOnError({ models: { fair: { Rose: frames(24, other) } } }, style)).not.toBeNull();
    expect(tryOnError({ models: { fair: { Rose: frames(3) } } }, style)).not.toBeNull();
    expect(tryOnError({ models: { olive: { Rose: frames(4) } } }, style)).not.toBeNull();
    expect(tryOnError({ colors: { Rose: 'pink' } }, style)).not.toBeNull();
    expect(tryOnError({ spins: { Rose: frames(4) } }, style)).not.toBeNull();
    expect(readTryOn({ video: 'x' }, style)).toEqual({});
  });
  it('finds model photos by tone and colour without regard to case', () => {
    const tryOn = { models: { dusky: { ' Rose ': frames(8) }, fair: { Rose: frames(4), Black: frames(4) } } };
    expect(tonesFor(tryOn, 'rose')).toEqual(['fair', 'dusky']);
    expect(tonesFor(tryOn, 'Black')).toEqual(['fair']);
    expect(spinFor(tryOn, 'rose', 'dusky')).toHaveLength(8);
    expect(spinFor(tryOn, 'Black', 'dusky')).toBeUndefined();
    expect(hasModelPhotos(tryOn)).toBe(true);
    expect(hasModelPhotos({ models: { fair: {} } })).toBe(false);
  });
  it('resolves colour names and custom shades', () => {
    expect(colorHex('Black')).toBe('#1d1a1c');
    expect(colorHex('Deep Plum')).toBe('#6b3355');
    expect(colorHex('rose', { Rose: '#ff0000' })).toBe('#ff0000');
    expect(colorHex('Unlisted')).toBeNull();
  });
  it('recolours fabric materials only, or exactly the configured ones', () => {
    expect(isGarmentMaterial('Bra_Lace')).toBe(true);
    expect(isGarmentMaterial('Skin')).toBe(false);
    expect(isGarmentMaterial('Skin', ['skin'])).toBe(true);
    expect(isGarmentMaterial('Lace', ['Satin'])).toBe(false);
  });
});
