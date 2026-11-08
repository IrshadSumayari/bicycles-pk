import { describe, expect, it, vi } from 'vitest';
vi.mock('./supabase', () => ({ supabase: {} }));
import { codeEmail, codeStatus, describeOffer, mailtoLink, type DiscountCode } from './discountCodes';
import { cartFingerprint } from './pendingCheckout';

const code: DiscountCode = {
  id: 'c1', code: 'LV-7KQ2XH', kind: 'welcome', description: null, customer_id: 'u1', discount_type: 'percentage',
  value: 15, min_amount: null, max_discount: null, valid_from: '2026-11-01T00:00:00Z', expires_at: '2026-12-01T00:00:00Z',
  max_uses: 1, used_count: 0, active: true, status: 'ready',
};

describe('discount codes', () => {
  it('describes percent and amount offers with their limits', () => {
    expect(describeOffer(code, 'PKR')).toBe('15% off');
    expect(describeOffer({ ...code, max_discount: 1000, min_amount: 3000 }, 'PKR')).toBe('15% off up to PKR 1,000 on PKR 3,000 or more');
    expect(describeOffer({ ...code, discount_type: 'fixed', value: 250 }, 'PKR')).toBe('PKR 250 off');
  });

  it('works out status the same way as the server', () => {
    const now = new Date('2026-11-15T00:00:00Z');
    expect(codeStatus(code, now)).toBe('ready');
    expect(codeStatus({ ...code, used_count: 1 }, now)).toBe('used');
    expect(codeStatus({ ...code, max_uses: null, used_count: 9 }, now)).toBe('ready');
    expect(codeStatus({ ...code, expires_at: '2026-11-10T00:00:00Z' }, now)).toBe('expired');
    expect(codeStatus({ ...code, valid_from: '2026-11-20T00:00:00Z' }, now)).toBe('scheduled');
    expect(codeStatus({ ...code, active: false }, now)).toBe('off');
  });

  it('writes an email draft and a mailto link that keeps line breaks', () => {
    const email = codeEmail(code, 'Ayesha', 'LadyVogue', 'PKR');
    expect(email.subject).toBe('Your LadyVogue discount code: LV-7KQ2XH');
    expect(email.body).toContain('Dear Ayesha,');
    expect(email.body).toContain('\nLV-7KQ2XH\n');
    expect(email.body).toContain('It can be used once.');
    const link = mailtoLink('ayesha@example.test', email);
    expect(link.startsWith('mailto:ayesha%40example.test?subject=Your%20LadyVogue')).toBe(true);
    expect(link).toContain('%0A');
  });

  it('gives a checkout with a code its own retry id, and leaves old ones unchanged', () => {
    const without = cartFingerprint([], 'u1', [], undefined);
    expect(cartFingerprint([], 'u1', [], undefined, '')).toBe(without);
    expect(cartFingerprint([], 'u1', [], undefined, 'lv-7kq2xh')).not.toBe(without);
    expect(cartFingerprint([], 'u1', [], undefined, 'lv-7kq2xh')).toBe(cartFingerprint([], 'u1', [], undefined, 'LV-7KQ2XH'));
  });
});
