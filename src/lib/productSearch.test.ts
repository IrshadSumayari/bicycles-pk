import { expect, it } from 'vitest';
import { scannerCode } from './productSearch';

it.each([
  ['  ABC-123 ', 'Enter', false, 'ABC-123'],
  ['001234567890', 'Enter', false, '001234567890'],
  ['ABC', 'a', false, null],
  ['', 'Enter', false, null],
  ['  ', 'Enter', false, null],
  ['ABC', 'Enter', true, null],
])('interprets scanner input %s / %s', (value, key, composing, expected) => {
  expect(scannerCode(value, key, composing)).toBe(expected);
});
