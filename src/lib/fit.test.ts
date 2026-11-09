import { describe, expect, it } from 'vitest';
import { adultFit, kidsFit, matchProductSize } from '../../shared/fit';

describe('bike fit', () => {
  it('picks the adult size by height and suggests a neighbour near a boundary', () => {
    expect(adultFit(172)?.size.size).toBe('M');
    expect(adultFit(172)?.alternative).toBeNull();
    expect(adultFit(177)?.alternative?.size).toBe('L');
    expect(adultFit(169)?.alternative?.size).toBe('S');
    expect(adultFit(140)?.size.size).toBe('XS');
    expect(adultFit(205)?.size.size).toBe('XL');
    expect(adultFit(90)).toBeNull();
  });
  it('works out frame sizes from inseam', () => {
    expect(adultFit(175, 80)).toMatchObject({ mtbFrameFromInseam: 18, roadFrameFromInseam: 54 });
    expect(adultFit(175, 20)).toMatchObject({ mtbFrameFromInseam: null, roadFrameFromInseam: null });
  });
  it('picks the kids wheel by height first, then age', () => {
    expect(kidsFit(125)?.wheel).toBe('20"');
    expect(kidsFit(90)?.wheel).toBe('10–12"');
    expect(kidsFit(98)?.wheel).toBe('14"');
    expect(kidsFit(null, 5)?.wheel).toBe('16"');
    expect(kidsFit(null, 11)?.wheel).toBe('24"');
    expect(kidsFit(200)).toBeNull();
    expect(kidsFit()).toBeNull();
  });
  it('matches a recommendation to the product sizes', () => {
    expect(matchProductSize(['S', 'M', 'L'], { size: 'm', frames: ['17–18"'] })).toBe('M');
    expect(matchProductSize(['15"', '17"', '19"'], { size: 'M', frames: ['17–18"'] })).toBe('17"');
    expect(matchProductSize(['52 cm', '54 cm', '56 cm'], { size: 'M', frames: ['53–55 cm'] })).toBe('54 cm');
    expect(matchProductSize(['16"', '20"'], { wheel: '20"' })).toBe('20"');
    expect(matchProductSize(['12"', '16"'], { wheel: '10–12"' })).toBe('12"');
    expect(matchProductSize(['One size'], { size: 'M' })).toBeNull();
  });
});
