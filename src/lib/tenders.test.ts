import { describe, expect, it } from 'vitest';
import { allocateTenders, Tender } from './tenders';

const ctx = { hasShift: true, hasCustomer: true, creditAvailable: 1000 };
const t = (over: Partial<Tender>): Tender => ({ key: Math.random().toString(), method: 'cash', amount: '', ...over });

describe('allocateTenders', () => {
  it('a single blank line pays the whole total and works out change', () => {
    const r = allocateTenders([t({ received: '5000' })], 4503.96, ctx);
    expect(r.ok).toBe(true);
    expect(r.lines[0].amount).toBe(4503.96);
    expect(r.lines[0].change).toBe(496.04);
  });

  it('the last blank line takes what is left', () => {
    const r = allocateTenders([
      t({ amount: '2000' }),
      t({ method: 'card', cardType: 'visa', cardLast4: '4242' }),
    ], 4500, ctx);
    expect(r.lines.map(l => l.amount)).toEqual([2000, 2500]);
    expect(r.remaining).toBe(0);
    expect(r.ok).toBe(true);
  });

  it('reports what is still to pay or overpaid', () => {
    expect(allocateTenders([t({ amount: '1000' })], 1500, ctx).remaining).toBe(500);
    expect(allocateTenders([t({ amount: '2000' })], 1500, ctx).remaining).toBe(-500);
  });

  it('cash needs a shift and enough cash received', () => {
    expect(allocateTenders([t({})], 100, { ...ctx, hasShift: false }).errors[0]).toBe('Open a cash shift to take cash');
    expect(allocateTenders([t({ received: '50' })], 100, ctx).errors[0]).toBe('Cash received is less than the amount');
  });

  it('card needs a type and the last 4 digits', () => {
    expect(allocateTenders([t({ method: 'card' })], 100, ctx).errors[0]).toBe('Choose the card type');
    expect(allocateTenders([t({ method: 'card', cardType: 'visa', cardLast4: '12' })], 100, ctx).errors[0])
      .toBe('Enter the last 4 digits from the slip');
  });

  it('store credit needs a customer and enough available credit', () => {
    expect(allocateTenders([t({ method: 'credit' })], 100, { ...ctx, hasCustomer: false }).ok).toBe(false);
    expect(allocateTenders([t({ method: 'credit' })], 1500, ctx).errors[0]).toBe('More than the customer’s available credit');
    expect(allocateTenders([t({ method: 'credit' })], 900, ctx).ok).toBe(true);
  });

  it('allows only one cash line', () => {
    const r = allocateTenders([t({ amount: '50' }), t({})], 100, ctx);
    expect(r.ok).toBe(false);
    expect(r.errors).toEqual(['Use one cash line', 'Use one cash line']);
  });
});
