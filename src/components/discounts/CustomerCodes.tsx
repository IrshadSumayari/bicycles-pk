import { useQuery, useQueryClient } from '@tanstack/react-query';
import { Copy, Mail, Ticket } from 'lucide-react';
import { Customer } from '../../types';
import { useApp } from '../../context/SupabaseAppContext';
import { queryKeys } from '../../lib/queryClient';
import { codeEmail, describeOffer, discountCodesService, formatCodeDate, mailtoLink } from '../../lib/discountCodes';
import { getErrorMessage } from '../../lib/errors';
import { swalConfig } from '../../lib/sweetAlert';

const STATUS_LABEL = { ready: 'Ready', used: 'Used', expired: 'Expired', scheduled: 'Not started', off: 'Switched off' } as const;

// A customer's discount codes, with copy, email (opens the staff member's own
// mail app) and, for managers, giving an existing customer a welcome code.
export function CustomerCodes({ customer }: { customer: Customer }) {
  const { state } = useApp();
  const queryClient = useQueryClient();
  const manager = ['admin', 'manager'].includes(state.currentUser?.role ?? '');
  const currency = state.settings.currency;
  const { data: codes = [], error, isPending } = useQuery({
    queryKey: queryKeys.customerDiscountCodes(customer.id),
    queryFn: () => discountCodesService.forCustomer(customer.id),
  });
  const canEmail = !!customer.email && customer.emailMarketingConsent === true;

  const copy = async (code: string) => {
    try {
      await navigator.clipboard.writeText(code);
      swalConfig.success(`${code} copied`);
    } catch {
      swalConfig.info(`Code: ${code}`);
    }
  };

  const issue = async () => {
    try {
      const code = await discountCodesService.issueWelcome(customer.id);
      await queryClient.invalidateQueries({ queryKey: queryKeys.customerDiscountCodes(customer.id) });
      swalConfig.success(`Welcome code ${code.code} created`);
    } catch (e) {
      swalConfig.error(getErrorMessage(e));
    }
  };

  return (
    <fieldset className="border border-border rounded-xl p-4 space-y-3">
      <legend className="font-semibold flex items-center gap-1"><Ticket className="h-4 w-4" />Discount codes</legend>
      {error && <p className="text-sm text-error">{getErrorMessage(error)}</p>}
      {!isPending && !error && codes.length === 0 && <p className="text-sm text-bodytext">No codes yet.</p>}
      {codes.map(code => {
        const email = codeEmail(code, customer.name, state.settings.storeName || 'our shop', currency);
        return (
          <div key={code.id} className="flex flex-wrap items-center gap-2 text-sm">
            <span className="font-mono font-semibold">{code.code}</span>
            <span>{describeOffer(code, currency)}</span>
            <span className={`badge ${code.status === 'ready' ? 'badge-success' : 'badge-secondary'}`}>{STATUS_LABEL[code.status]}</span>
            {code.expires_at && <span className="text-xs text-bodytext">until {formatCodeDate(code.expires_at)}</span>}
            {code.status === 'ready' && (
              <span className="ml-auto flex gap-1">
                <button type="button" className="btn btn-secondary btn-sm" onClick={() => void copy(code.code)} title="Copy code">
                  <Copy className="h-4 w-4" />
                </button>
                {canEmail && (
                  <a className="btn btn-secondary btn-sm" href={mailtoLink(customer.email, email)} title="Write an email with this code">
                    <Mail className="h-4 w-4" />
                  </a>
                )}
              </span>
            )}
          </div>
        );
      })}
      {codes.some(c => c.status === 'ready') && !canEmail && (
        <p className="text-xs text-bodytext">Email appears once the customer has an email address and has agreed to email offers.</p>
      )}
      {manager && !codes.some(c => c.kind === 'welcome') && (
        <button type="button" className="btn btn-secondary btn-sm" onClick={() => void issue()}>Give welcome code</button>
      )}
    </fieldset>
  );
}
