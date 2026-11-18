import { describe, expect, it } from 'vitest';
import { rangeFor } from './reportDates';

describe('report date presets in the shop timezone', () => {
  const monday = new Date('2026-10-19T12:00:00+05:00');
  it('uses today for today and the initial custom range', () => {
    for (const preset of ['today', 'custom'] as const) {
      expect(rangeFor(preset, monday)).toEqual({
        from: '2026-10-19',
        to: '2026-10-19',
      });
    }
  });
  it('uses Karachi day even on the preceding UTC day', () => {
    expect(rangeFor('today', new Date('2026-12-31T19:30:00Z'))).toEqual({
      from: '2027-01-01',
      to: '2027-01-01',
    });
  });
  it('keeps the preceding Karachi day before midnight', () => {
    expect(rangeFor('today', new Date('2026-12-31T18:59:59Z'))).toEqual({
      from: '2026-12-31',
      to: '2026-12-31',
    });
  });
  it('finds yesterday across a year boundary', () => {
    expect(
      rangeFor('yesterday', new Date('2027-01-01T12:00:00+05:00')),
    ).toEqual({ from: '2026-12-31', to: '2026-12-31' });
  });
  it('finds yesterday across a leap month boundary', () => {
    expect(
      rangeFor('yesterday', new Date('2028-03-01T12:00:00+05:00')),
    ).toEqual({ from: '2028-02-29', to: '2028-02-29' });
  });
  it('starts the week on Monday and ends on Sunday', () => {
    expect(rangeFor('this_week', monday)).toEqual({
      from: '2026-10-19',
      to: '2026-10-25',
    });
    expect(
      rangeFor('this_week', new Date('2026-10-25T12:00:00+05:00')),
    ).toEqual({ from: '2026-10-19', to: '2026-10-25' });
  });
  it('handles a week spanning years', () => {
    expect(
      rangeFor('this_week', new Date('2027-01-01T12:00:00+05:00')),
    ).toEqual({ from: '2026-12-28', to: '2027-01-03' });
  });
  it('uses full calendar months, including a leap February', () => {
    expect(rangeFor('this_month', monday)).toEqual({
      from: '2026-10-01',
      to: '2026-10-31',
    });
    expect(
      rangeFor('this_month', new Date('2028-02-29T12:00:00+05:00')),
    ).toEqual({ from: '2028-02-01', to: '2028-02-29' });
  });
  it('finds last month from the end of a long month', () => {
    expect(
      rangeFor('last_month', new Date('2027-03-31T12:00:00+05:00')),
    ).toEqual({ from: '2027-02-01', to: '2027-02-28' });
  });
  it('finds last month across years', () => {
    expect(
      rangeFor('last_month', new Date('2027-01-15T12:00:00+05:00')),
    ).toEqual({ from: '2026-12-01', to: '2026-12-31' });
  });
  it('does not modify the supplied Date', () => {
    const timestamp = monday.getTime();
    rangeFor('last_month', monday);
    expect(monday.getTime()).toBe(timestamp);
  });
  it('rejects an invalid date', () => {
    expect(() => rangeFor('today', new Date('invalid'))).toThrow(
      'Choose a valid report date',
    );
  });
});
