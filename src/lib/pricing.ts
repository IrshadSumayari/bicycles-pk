import { CartItem } from '../types';

// Money is rounded to 2 decimals at each step shown to the customer so the
// screen, the receipt and the database all agree.
export function roundMoney(value: number): number {
  return Math.round((value + Number.EPSILON) * 100) / 100;
}

// Unit price of one cart line before discounts.
export function unitPrice(item: CartItem): number {
  return item.product.price;
}

// Price of the whole line before discounts.
export function lineGross(item: CartItem): number {
  return roundMoney(unitPrice(item) * item.quantity);
}

// Manual discount amount for a line, given as a percentage or a fixed amount.
// Never more than the line itself.
export function lineDiscountAmount(
  item: CartItem,
  discount: number,
  discountType: 'percentage' | 'fixed'
): number {
  const gross = lineGross(item);
  const amount = discountType === 'percentage' ? (gross * discount) / 100 : discount;
  return roundMoney(Math.min(Math.max(amount, 0), gross));
}

export interface CartTotals {
  subtotal: number;
  manualDiscount: number;
  orderDiscount: number;
  totalDiscount: number;
  taxableAmount: number;
  taxAmount: number;
  total: number;
}

// Totals for a cart, worked out the same way as the server's quote_sale():
// - manual line discounts come from each item's `discount`
// - `orderDiscount` (automatic promotions) is spread over lines by value,
//   rounded per line with the remainder on the last line
// - tax is rounded per line and applies only to taxable products
export function calculateTotals(
  cart: CartItem[],
  taxRatePercent: number,
  orderDiscount = 0
): CartTotals {
  const lines = cart.map(item => {
    const gross = lineGross(item);
    const discount = roundMoney(Math.min(item.discount || 0, gross));
    return { gross, net: roundMoney(gross - discount), discount, taxable: item.product.taxable !== false };
  });

  const subtotal = roundMoney(lines.reduce((sum, l) => sum + l.gross, 0));
  const manualDiscount = roundMoney(lines.reduce((sum, l) => sum + l.discount, 0));
  const netBeforeOrderDiscount = roundMoney(subtotal - manualDiscount);
  const appliedOrderDiscount = roundMoney(Math.min(Math.max(orderDiscount, 0), netBeforeOrderDiscount));

  let remaining = appliedOrderDiscount;
  let taxableAmount = 0;
  let taxAmount = 0;
  lines.forEach((line, i) => {
    let share = i === lines.length - 1
      ? remaining
      : netBeforeOrderDiscount > 0 ? roundMoney(appliedOrderDiscount * line.net / netBeforeOrderDiscount) : 0;
    share = Math.min(share, line.net);
    remaining = roundMoney(remaining - share);
    const net = roundMoney(line.net - share);
    if (line.taxable) {
      taxableAmount += net;
      taxAmount += roundMoney(net * taxRatePercent / 100);
    }
  });

  taxableAmount = roundMoney(taxableAmount);
  taxAmount = roundMoney(taxAmount);
  const totalDiscount = roundMoney(manualDiscount + appliedOrderDiscount);
  const total = roundMoney(subtotal - totalDiscount + taxAmount);

  return {
    subtotal,
    manualDiscount,
    orderDiscount: appliedOrderDiscount,
    totalDiscount,
    taxableAmount,
    taxAmount,
    total,
  };
}
