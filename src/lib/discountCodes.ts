import { supabase } from './supabase';
import { queryClient, queryKeys } from './queryClient';
import type { Json } from './database.types';

export type CodeDiscountType = 'percentage' | 'fixed';
export type CodeStatus = 'ready' | 'used' | 'expired' | 'scheduled' | 'off';

export interface DiscountCode {
  id: string;
  code: string;
  kind: 'welcome' | 'manual';
  description: string | null;
  customer_id: string | null;
  discount_type: CodeDiscountType;
  value: number;
  min_amount: number | null;
  max_discount: number | null;
  valid_from: string;
  expires_at: string | null;
  max_uses: number | null;
  used_count: number;
  active: boolean;
  status: CodeStatus;
}

export interface DiscountCodeRow extends DiscountCode {
  customer: { name: string; phone: string | null } | null;
}

export interface WelcomeSettings {
  welcome_enabled: boolean;
  welcome_type: CodeDiscountType;
  welcome_value: number;
  welcome_valid_days: number;
  welcome_min_amount: number | null;
  welcome_max_discount: number | null;
}

export interface DiscountCodeInput {
  id?: string;
  code?: string;
  description?: string;
  customer_id?: string | null;
  discount_type: CodeDiscountType;
  value: number;
  min_amount?: number | null;
  max_discount?: number | null;
  valid_from?: string | null;
  expires_at?: string | null;
  max_uses?: number | null;
  active?: boolean;
}

const invalidate = () => {
  void queryClient.invalidateQueries({ queryKey: queryKeys.discountCodes });
};

// Same as the table's status, worked out in the browser for the list screen
export function codeStatus(code: Pick<DiscountCode, 'active' | 'max_uses' | 'used_count' | 'expires_at' | 'valid_from'>, now = new Date()): CodeStatus {
  if (!code.active) return 'off';
  if (code.max_uses !== null && code.used_count >= code.max_uses) return 'used';
  if (code.expires_at && new Date(code.expires_at) <= now) return 'expired';
  if (new Date(code.valid_from) > now) return 'scheduled';
  return 'ready';
}

export const discountCodesService = {
  async settings(): Promise<WelcomeSettings> {
    const { data, error } = await supabase.from('discount_code_settings').select('*').single();
    if (error) throw error;
    return {
      welcome_enabled: data.welcome_enabled,
      welcome_type: data.welcome_type as CodeDiscountType,
      welcome_value: Number(data.welcome_value),
      welcome_valid_days: data.welcome_valid_days,
      welcome_min_amount: data.welcome_min_amount === null ? null : Number(data.welcome_min_amount),
      welcome_max_discount: data.welcome_max_discount === null ? null : Number(data.welcome_max_discount),
    };
  },
  async saveSettings(settings: WelcomeSettings): Promise<void> {
    const { error } = await supabase.rpc('save_discount_code_settings', { p: settings as unknown as Json });
    if (error) throw error;
    invalidate();
  },
  async list(): Promise<DiscountCodeRow[]> {
    const { data, error } = await supabase
      .from('discount_codes')
      .select('*, customer:customers(name, phone)')
      .order('created_at', { ascending: false })
      .limit(200);
    if (error) throw error;
    return data.map(row => {
      const code = {
        ...row,
        kind: row.kind as DiscountCode['kind'],
        discount_type: row.discount_type as CodeDiscountType,
        value: Number(row.value),
        min_amount: row.min_amount === null ? null : Number(row.min_amount),
        max_discount: row.max_discount === null ? null : Number(row.max_discount),
      };
      return { ...code, status: codeStatus(code) };
    });
  },
  async save(input: DiscountCodeInput): Promise<DiscountCode> {
    const { data, error } = await supabase.rpc('save_discount_code', { p: input as unknown as Json });
    if (error) throw error;
    invalidate();
    return data as unknown as DiscountCode;
  },
  async forCustomer(customerId: string): Promise<DiscountCode[]> {
    const { data, error } = await supabase.rpc('customer_discount_codes', { p_customer_id: customerId });
    if (error) throw error;
    return data as unknown as DiscountCode[];
  },
  async issueWelcome(customerId: string): Promise<DiscountCode> {
    const { data, error } = await supabase.rpc('issue_customer_welcome_code', { p_customer_id: customerId });
    if (error) throw error;
    invalidate();
    return data as unknown as DiscountCode;
  },
};

// "15% off" / "PKR 250 off", with the limits staff must mention
export function describeOffer(code: Pick<DiscountCode, 'discount_type' | 'value' | 'min_amount' | 'max_discount'>, currency: string): string {
  const amount = (n: number) => `${currency} ${Number(n).toLocaleString('en-PK')}`;
  const parts = [code.discount_type === 'percentage' ? `${Number(code.value)}% off` : `${amount(code.value)} off`];
  if (code.max_discount) parts.push(`up to ${amount(code.max_discount)}`);
  if (code.min_amount) parts.push(`on ${amount(code.min_amount)} or more`);
  return parts.join(' ');
}

export function formatCodeDate(iso: string | null): string {
  return iso ? new Date(iso).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' }) : 'No end date';
}

// A ready-to-send email the cashier opens in their own mail app. Nothing is sent by the POS.
export function codeEmail(code: DiscountCode, customerName: string, shopName: string, currency: string): { subject: string; body: string } {
  const offer = describeOffer(code, currency);
  const until = code.expires_at ? ` It is valid until ${formatCodeDate(code.expires_at)}.` : '';
  const once = code.max_uses === 1 ? ' It can be used once.' : '';
  return {
    subject: `Your ${shopName} discount code: ${code.code}`,
    body: [
      `Dear ${customerName || 'customer'},`,
      '',
      `Thank you for shopping with ${shopName}. Here is your discount code for ${offer}:`,
      '',
      code.code,
      '',
      `Show this code at the counter when you pay.${until}${once}`,
      '',
      shopName,
    ].join('\n'),
  };
}

export function mailtoLink(to: string, email: { subject: string; body: string }): string {
  return `mailto:${encodeURIComponent(to)}?subject=${encodeURIComponent(email.subject)}&body=${encodeURIComponent(email.body)}`;
}
