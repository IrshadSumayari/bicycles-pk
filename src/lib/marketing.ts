import { supabase } from './supabase';

export type MarketingChannel = 'email' | 'sms';
export type Consent = boolean | null;
export type AudienceMember = { name: string; contact: string; source: string; consent_at: string | null; total_count: number };
export type CampaignDraft = { id: string; name: string; channel: MarketingChannel; subject: string; body: string; status: string; created_at: string; updated_at: string; created_by: string };

export const marketingService = {
  async audience(channel: MarketingChannel, query = '', offset = 0, limit = 50): Promise<AudienceMember[]> {
    const { data, error } = await supabase.rpc('marketing_audience', { p_channel: channel, p_query: query, p_offset: offset, p_limit: limit });
    if (error) throw error;
    return data;
  },
  async drafts(): Promise<CampaignDraft[]> {
    const { data, error } = await supabase.from('marketing_campaigns').select('*').order('updated_at', { ascending: false }).limit(100);
    if (error) throw error;
    return data as CampaignDraft[];
  },
  async save(draft: Pick<CampaignDraft, 'id' | 'name' | 'channel' | 'subject' | 'body'>): Promise<void> {
    const values = { name: draft.name, channel: draft.channel, subject: draft.subject, body: draft.body };
    const { data, error } = await supabase.from('marketing_campaigns').update(values).eq('id', draft.id).select('id').maybeSingle();
    if (error) throw error;
    if (!data) {
      const { error: createdError } = await supabase.from('marketing_campaigns').insert({ id: draft.id, ...values });
      if (createdError) throw createdError;
    }
  },
};

// Prevent spreadsheet formula evaluation in exported user-supplied cells. A valid
// international phone number cannot hold a formula, and SMS providers reject a
// leading apostrophe, so +923001234567 is exported as is.
const PHONE = /^\+[1-9][0-9]{7,14}$/;
export function marketingCsv(rows: AudienceMember[]): string {
  const cell = (value: string) => '"' + (/^[\s]*[=+@-]/.test(value) && !PHONE.test(value) ? "'" + value : value).replaceAll('"', '""') + '"';
  return '\uFEFF' + [['Name', 'Contact', 'Source', 'Consent recorded'], ...rows.map(r => [r.name, r.contact, r.source, r.consent_at ?? ''])].map(row => row.map(cell).join(',')).join('\r\n');
}
