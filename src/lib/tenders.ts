import { roundMoney } from './pricing';

export type TenderMethod = 'cash' | 'card' | 'digital' | 'credit';

export interface Tender {
  key: string;
  method: TenderMethod;
  amount: string; // '' = take whatever is left (only the last line)
  received?: string; // cash handed over
  reference?: string;
  cardType?: string;
  cardLast4?: string;
  bankName?: string;
  holderName?: string;
}

export interface TenderAllocation {
  lines: { tender: Tender; amount: number; change: number }[];
  errors: (string | undefined)[];
  remaining: number;
  ok: boolean;
}

// Works out what each payment line pays and whether the sale can be completed.
// A blank amount on the last line takes the rest of the total.
export function allocateTenders(
  tenders: Tender[],
  total: number,
  context: { hasShift: boolean; hasCustomer: boolean; creditAvailable: number }
): TenderAllocation {
  const errors: (string | undefined)[] = tenders.map(() => undefined);
  const explicit = tenders.map(t => (t.amount === '' ? null : Number(t.amount)));
  const fixedSum = roundMoney(explicit.reduce<number>((sum, a) => sum + (a !== null && Number.isFinite(a) ? a : 0), 0));

  const lines = tenders.map((tender, i) => {
    let amount: number;
    if (explicit[i] === null) {
      amount = i === tenders.length - 1 ? Math.max(roundMoney(total - fixedSum), 0) : 0;
    } else {
      amount = Number.isFinite(explicit[i]) ? roundMoney(explicit[i] as number) : NaN;
    }

    let change = 0;
    if (!Number.isFinite(amount) || amount <= 0) {
      errors[i] = 'Enter an amount';
      amount = Number.isFinite(amount) ? amount : 0;
    }

    switch (tender.method) {
      case 'cash': {
        if (!context.hasShift) errors[i] = 'Open a cash shift to take cash';
        const received = tender.received === undefined || tender.received === '' ? amount : Number(tender.received);
        if (!Number.isFinite(received) || received < amount) errors[i] = errors[i] ?? 'Cash received is less than the amount';
        else change = roundMoney(received - amount);
        break;
      }
      case 'card':
        if (!tender.cardType) errors[i] = errors[i] ?? 'Choose the card type';
        else if (!/^\d{4}$/.test(tender.cardLast4 ?? '')) errors[i] = errors[i] ?? 'Enter the last 4 digits from the slip';
        break;
      case 'credit':
        if (!context.hasCustomer) errors[i] = 'Select a customer for store credit';
        else if (amount > context.creditAvailable) errors[i] = errors[i] ?? 'More than the customer’s available credit';
        break;
    }
    return { tender, amount, change };
  });

  if (tenders.filter(t => t.method === 'cash').length > 1) {
    tenders.forEach((t, i) => { if (t.method === 'cash') errors[i] = errors[i] ?? 'Use one cash line'; });
  }

  const paid = roundMoney(lines.reduce((sum, l) => sum + l.amount, 0));
  const remaining = roundMoney(total - paid);
  const ok = remaining === 0 && errors.every(e => !e) && lines.length > 0;
  return { lines, errors, remaining, ok };
}
