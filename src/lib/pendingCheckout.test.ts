import { describe, expect, it } from 'vitest';
import type { CartItem, Product } from '../types';
import {
  cartFingerprint,
  clearPendingCheckout,
  pendingFor,
  PENDING_CHECKOUT_KEY,
  PENDING_CHECKOUT_TTL,
  readPendingCheckout,
  savePendingCheckout,
} from './pendingCheckout';

const line = (id = 'variant-1'): CartItem => ({
  product: { id } as Product,
  quantity: 1,
  discount: 0,
  discountType: 'fixed',
  subtotal: 100,
});
function storage() {
  const values = new Map<string, string>();
  return {
    getItem: (key: string) => values.get(key) ?? null,
    setItem: (key: string, value: string) => {
      values.set(key, value);
    },
    removeItem: (key: string) => {
      values.delete(key);
    },
  };
}
const fingerprint = (cart = [line()], customer?: string, amount = 100) =>
  cartFingerprint(cart, customer, [{ method: 'card', amount }]);

describe('pending checkout', () => {
  it('reuses the same ID after saving and reopening the same basket', () => {
    const session = storage();
    const first = pendingFor(null, fingerprint(), 100, () => 'first');
    savePendingCheckout(session, first);
    expect(
      pendingFor(
        readPendingCheckout(session),
        fingerprint(),
        200,
        () => 'second',
      ).requestId,
    ).toBe('first');
  });
  it('keeps the ID when only the cash handed over changes', () => {
    const cash = (tendered: number) =>
      cartFingerprint([line()], undefined, [{ method: 'cash', amount: 100, tendered }]);
    const first = pendingFor(null, cash(100), 0, () => 'first');
    expect(pendingFor(first, cash(500), 100, () => 'new').requestId).toBe('first');
  });
  it('creates another ID for changed cart, customer or tender amounts', () => {
    const first = pendingFor(null, fingerprint(), 0, () => 'first');
    const changed = [
      fingerprint([{ ...line(), quantity: 2 }]),
      fingerprint([line()], 'another-customer'),
      fingerprint([line()], undefined, 99),
      fingerprint([{ ...line(), discount: 10 }]),
    ];
    changed.forEach((value) =>
      expect(pendingFor(first, value, 100, () => 'new').requestId).toBe('new'),
    );
  });
  it('ignores expired and future-dated records', () => {
    const first = pendingFor(null, fingerprint(), 100, () => 'first');
    expect(
      pendingFor(
        first,
        fingerprint(),
        100 + PENDING_CHECKOUT_TTL,
        () => 'expired',
      ).requestId,
    ).toBe('expired');
    expect(pendingFor(first, fingerprint(), 99, () => 'future').requestId).toBe(
      'future',
    );
  });
  it('clears the saved record on success or cart clear', () => {
    const session = storage();
    savePendingCheckout(
      session,
      pendingFor(null, fingerprint(), 100, () => 'first'),
    );
    clearPendingCheckout(session);
    expect(readPendingCheckout(session)).toBeNull();
  });
  it('ignores malformed records', () => {
    const session = storage();
    for (const raw of ['broken json', '{}', '{"requestId":2}', 'null']) {
      session.setItem(PENDING_CHECKOUT_KEY, raw);
      expect(readPendingCheckout(session)).toBeNull();
    }
  });
  it('is stable across line order and does not keep card details in storage', () => {
    expect(fingerprint([line('b'), line('a')])).toBe(
      fingerprint([line('a'), line('b')]),
    );
    const value = cartFingerprint([line()], undefined, [
      { method: 'card', amount: 100, cardLast4: '4242', reference: 'slip' },
    ]);
    expect(value).not.toContain('4242');
    expect(value).not.toContain('slip');
  });
});

it('changes the pending checkout identity when the salesperson changes', () => {
  const first = cartFingerprint([line()], undefined, [{ method: 'card', amount: 100 }], 'seller-a');
  const second = cartFingerprint([line()], undefined, [{ method: 'card', amount: 100 }], 'seller-b');
  expect(first).not.toBe(second);
});

it('treats a removed promotion as a different sale, whatever the order', () => {
  const card = [{ method: 'card' as const, amount: 100 }];
  const plain = cartFingerprint([line()], undefined, card);
  const skipped = cartFingerprint([line()], undefined, card, undefined, undefined, ['p1', 'p2']);
  expect(skipped).not.toBe(plain);
  expect(cartFingerprint([line()], undefined, card, undefined, undefined, ['p2', 'p1'])).toBe(skipped);
  // Nothing removed keeps the fingerprint saved by older versions
  expect(cartFingerprint([line()], undefined, card, undefined, undefined, [])).toBe(plain);
});
