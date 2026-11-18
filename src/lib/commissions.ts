import { supabase } from './supabase';
export type CommissionPerson = { id: string; name: string; active: boolean; enabled: boolean; kind: 'fixed' | 'percentage'; rate: number };
export type CommissionSummary = { user_id: string; name: string; balance: number; earned: number; reversed: number; paid: number; invoices: number };
export type CommissionOverview = {
  people: CommissionPerson[]; summary: CommissionSummary[]; can_manage: boolean; total_count: number;
  entries: { id: string; user_id: string; name: string; kind: 'earned' | 'return' | 'payout'; amount: number; note: string | null; created_at: string; invoice_number: string | null; rule_kind: string | null; rule_rate: number | null; basis: number | null }[];
};
export const commissionsService = {
  async branches() {
    const { data, error } = await supabase.rpc('commission_branches'); if (error) throw error;
    return data as unknown as { id: string; name: string }[];
  },
  async sellers(branch: string) {
    const { data, error } = await supabase.rpc('commission_sellers', { p_branch: branch }); if (error) throw error;
    return data as unknown as { id: string; name: string }[];
  },
  async overview(branch: string, from: string, to: string, person: string, offset: number) {
    const { data, error } = await supabase.rpc('commission_overview', { p: { branch_id: branch, from, to, user_id: person || null, offset } }); if (error) throw error;
    return data as unknown as CommissionOverview;
  },
  async saveRule(branch: string, person: CommissionPerson) {
    const { error } = await supabase.rpc('save_commission_rule', { p_branch: branch, p_user: person.id, p_kind: person.kind, p_rate: person.rate, p_enabled: person.enabled }); if (error) throw error;
  },
  async payout(pending: { branch: string; person: string; amount: number; note: string; requestId: string }) {
    const { error } = await supabase.rpc('record_commission_payout', { p_branch: pending.branch, p_user: pending.person, p_amount: pending.amount, p_note: pending.note, p_request: pending.requestId }); if (error) throw error;
  },
};
