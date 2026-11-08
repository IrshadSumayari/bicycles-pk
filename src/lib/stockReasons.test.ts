import { describe, expect, it } from 'vitest'
import { stockReasons } from './stockReasons'

describe('stock adjustment reasons', () => {
  it('offers built-in reasons when none are set up, with Other last', () => {
    const reasons = stockReasons([])
    expect(reasons[0]).toBe('New stock received')
    expect(reasons.at(-1)).toBe('Other')
  })
  it('puts Settings reasons first without duplicating Other', () => {
    expect(stockReasons(['Gift', 'other', 'Damaged'])).toEqual(['Gift', 'Damaged', 'New stock received', 'Stock count correction', 'Lost or stolen', 'Returned to supplier', 'Other'])
  })
})
