import { describe, expect, it } from 'vitest';
import { calculateTotals, lineDiscountAmount, lineGross, roundMoney } from './pricing';
import { CartItem, Product } from '../types';

function product(overrides: Partial<Product> = {}): Product {
  return {
    id: 'p1',
    styleId: 's1',
    kind: 'item',
    name: 'Urban City Bike',
    sku: 'KUR-NAVY-L',
    price: 2500,
    cost: 1200,
    stock: 10,
    minStock: 0,
    category: 'Clothing',
    description: '',
    taxable: true,
    active: true,
    createdAt: new Date(0),
    updatedAt: new Date(0),
    ...overrides,
  };
}

function item(overrides: Partial<CartItem> = {}, productOverrides: Partial<Product> = {}): CartItem {
  return {
    product: product(productOverrides),
    quantity: 1,
    discount: 0,
    discountType: 'fixed',
    subtotal: 0,
    ...overrides,
  };
}

describe('roundMoney', () => {
  it('rounds half up to 2 decimals', () => {
    expect(roundMoney(1.005)).toBe(1.01);
    expect(roundMoney(2.675)).toBe(2.68);
    expect(roundMoney(10)).toBe(10);
  });
});

describe('lineGross', () => {
  it('multiplies price by quantity', () => {
    expect(lineGross(item({ quantity: 3 }))).toBe(7500);
  });
});

describe('lineDiscountAmount', () => {
  it('computes percentage discounts on the whole line', () => {
    expect(lineDiscountAmount(item({ quantity: 2 }), 10, 'percentage')).toBe(500);
  });

  it('never discounts more than the line', () => {
    expect(lineDiscountAmount(item(), 9999, 'fixed')).toBe(2500);
    expect(lineDiscountAmount(item(), -50, 'fixed')).toBe(0);
  });
});

describe('calculateTotals', () => {
  it('adds tax on the discounted amount', () => {
    const totals = calculateTotals([item({ quantity: 2, discount: 500 })], 17);
    expect(totals).toMatchObject({
      subtotal: 5000,
      manualDiscount: 500,
      totalDiscount: 500,
      taxableAmount: 4500,
      taxAmount: 765,
      total: 5265,
    });
  });

  it('does not tax non-taxable products', () => {
    const totals = calculateTotals(
      [item(), item({}, { id: 'p2', price: 1000, taxable: false })],
      10
    );
    expect(totals.subtotal).toBe(3500);
    expect(totals.taxableAmount).toBe(2500);
    expect(totals.taxAmount).toBe(250);
    expect(totals.total).toBe(3750);
  });

  it('spreads order discounts over taxable and non-taxable lines', () => {
    const totals = calculateTotals(
      [item({}, { price: 3000 }), item({}, { id: 'p2', price: 1000, taxable: false })],
      10,
      400
    );
    // 3000 of 4000 is taxable, so 300 of the 400 discount reduces the taxable base
    expect(totals.taxableAmount).toBe(2700);
    expect(totals.taxAmount).toBe(270);
    expect(totals.total).toBe(3870);
  });

  it('caps the order discount at the cart value', () => {
    const totals = calculateTotals([item()], 0, 10000);
    expect(totals.orderDiscount).toBe(2500);
    expect(totals.total).toBe(0);
  });

  it('keeps totals consistent: subtotal - discount + tax = total', () => {
    const totals = calculateTotals(
      [item({ quantity: 3, discount: 333.33 }), item({}, { id: 'p2', price: 999.99 })],
      17,
      123.45
    );
    expect(roundMoney(totals.subtotal - totals.totalDiscount + totals.taxAmount)).toBe(totals.total);
  });

  it('returns zeros for an empty cart', () => {
    expect(calculateTotals([], 17).total).toBe(0);
  });
});
