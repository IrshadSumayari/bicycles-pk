import type { CartItem } from '../types';
import type { PaymentInput } from './services';

export const PENDING_CHECKOUT_KEY = 'pos.pendingCheckout';
export const PENDING_CHECKOUT_TTL = 30 * 60 * 1000;
export type PendingCheckout = {
  requestId: string;
  cartFingerprint: string;
  createdAt: number;
};
type CheckoutStorage = Pick<Storage, 'getItem' | 'setItem' | 'removeItem'>;

export function cartFingerprint(
  cart: CartItem[],
  customerId: string | undefined,
  payments: PaymentInput[],
  salespersonId?: string,
  discountCode?: string,
  skippedPromotions: readonly string[] = [],
): string {
  const lines = cart
    .map((line) =>
      JSON.stringify([
        line.product.id,
        line.quantity,
        line.discount,
        line.discountType,
      ]),
    )
    .sort();
  // Cash received only changes the change given, not the sale, so a retry
  // with a different amount handed over must keep the same request id.
  const tenders = payments
    .map((payment) => JSON.stringify([payment.method, payment.amount ?? 0]))
    .sort();
  const fingerprint = [lines, customerId ?? null, tenders, salespersonId ?? null];
  // Added only when used so pending checkouts saved before codes existed still match
  if (discountCode) fingerprint.push(discountCode.trim().toUpperCase());
  // A removed promotion changes the total, so it is a different sale
  if (skippedPromotions.length) fingerprint.push(['skip', ...[...skippedPromotions].sort()]);
  return JSON.stringify(fingerprint);
}

export function pendingFor(
  previous: PendingCheckout | null,
  fingerprint: string,
  now: number,
  createId: () => string,
): PendingCheckout {
  if (
    previous &&
    previous.cartFingerprint === fingerprint &&
    now >= previous.createdAt &&
    now - previous.createdAt < PENDING_CHECKOUT_TTL
  )
    return previous;
  return {
    requestId: createId(),
    cartFingerprint: fingerprint,
    createdAt: now,
  };
}

export function readPendingCheckout(
  storage: CheckoutStorage,
): PendingCheckout | null {
  try {
    const raw: unknown = JSON.parse(
      storage.getItem(PENDING_CHECKOUT_KEY) ?? 'null',
    );
    if (
      typeof raw === 'object' &&
      raw !== null &&
      'requestId' in raw &&
      typeof raw.requestId === 'string' &&
      raw.requestId &&
      'cartFingerprint' in raw &&
      typeof raw.cartFingerprint === 'string' &&
      'createdAt' in raw &&
      typeof raw.createdAt === 'number' &&
      Number.isFinite(raw.createdAt)
    ) {
      return {
        requestId: raw.requestId,
        cartFingerprint: raw.cartFingerprint,
        createdAt: raw.createdAt,
      };
    }
  } catch {
    /* Unavailable or malformed storage cannot supply a retry ID. Saving must still succeed before posting. */
  }
  return null;
}

export function savePendingCheckout(
  storage: CheckoutStorage,
  record: PendingCheckout,
): void {
  storage.setItem(PENDING_CHECKOUT_KEY, JSON.stringify(record));
}
export function clearPendingCheckout(storage: CheckoutStorage): void {
  storage.removeItem(PENDING_CHECKOUT_KEY);
}
