import { describe, expect, it } from 'vitest';
import { customerSearchFilter, customerSearchTerm } from './customerSearch';

describe('customer phone search', () => {
  it.each([
    ['0300-123 4567', '+923001234567'],
    ['+92 (300) 123-4567', '+923001234567'],
    ['00923001234567', '+923001234567'],
    ['923001234567', '+923001234567'],
    ['0300', '+92300'],
    ['1234567', '1234567'],
    ['  Ali Khan  ', 'Ali Khan'],
    ['', ''],
  ])('normalizes %s', (input, expected) =>
    expect(customerSearchTerm(input)).toBe(expected),
  );
  it('searches name, normalized phone and email', () => {
    expect(customerSearchFilter('0300')).toBe(
      'name.ilike."%0300%",phone.ilike."%+92300%",email.ilike."%0300%"',
    );
  });
  it('quotes punctuation and escapes LIKE wildcards', () => {
    expect(customerSearchFilter('a,b(%)_"\\')).toBe(
      String.raw`name.ilike."%a,b(\\%)\\_\"\\\\%",phone.ilike."%a,b(\\%)\\_\"\\\\%",email.ilike."%a,b(\\%)\\_\"\\\\%"`,
    );
  });
});
