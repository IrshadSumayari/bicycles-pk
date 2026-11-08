import {Input}from'@/components/ui/input';
import {DataTable}from'@/components/shared/DataTable';
import {ModalShell}from'@/components/shared/ModalShell';
import React, { useState } from 'react';
import { Wallet, ArrowDownToLine, ArrowUpFromLine, Lock, X, Undo2 } from 'lucide-react';
import { ShiftHistory } from '../reports/ShiftHistory';
import { ReturnModal } from './ReturnModal';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useApp } from '../../context/SupabaseAppContext';
import { CashShift, shiftsService } from '../../lib/services';
import { queryKeys } from '../../lib/queryClient';
import { swalConfig } from '../../lib/sweetAlert';
import { getErrorMessage } from '../../lib/errors';

// The cashier's open shift: required before taking cash.
export function useCashShift() {
  return useQuery({ queryKey: queryKeys.cashShift, queryFn: () => shiftsService.current(), staleTime: 10_000 });
}

type Dialog = null | 'open' | 'in' | 'out' | 'close' | 'return' | 'history';

export function CashShiftBar() {
  const { state } = useApp();
  const queryClient = useQueryClient();
  const { data: shift, isLoading } = useCashShift();
  const [dialog, setDialog] = useState<Dialog>(null);
  const [closed, setClosed] = useState<CashShift | null>(null);
  const currency = state.settings.currency;
  const money = (n: number) => `${currency} ${n.toFixed(2)}`;

  const refresh = (value: CashShift | null) => queryClient.setQueryData(queryKeys.cashShift, value);

  if (isLoading) return null;

  return (
    <>
      <div className={`flex flex-wrap items-center justify-between gap-3 px-4 py-2 text-sm border-b ${
        shift ? 'bg-lightsuccess border-lightsuccess text-success' : 'bg-lightwarning border-lightwarning text-warning'}`}>
        {shift ? (
          <>
            <span className="flex items-center gap-2">
              <Wallet className="h-4 w-4" />
              <span className="font-semibold">{shift.sessionNo}</span>
              <span>open since {shift.openedAt.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</span>
              <span className="hidden md:inline">· cash in drawer {money(shift.expectedCash)}</span>
            </span>
            <span className="flex flex-wrap gap-2">
              <button type="button" onClick={() => setDialog('history')} className="btn btn-secondary btn-sm">My shifts</button>
              <button type="button" onClick={() => setDialog('return')} className="btn btn-secondary btn-sm">
                <Undo2 className="h-4 w-4" /><span>Return / exchange</span>
              </button>
              <button type="button" onClick={() => setDialog('in')} className="btn btn-secondary btn-sm">
                <ArrowDownToLine className="h-4 w-4" /><span>Cash in</span>
              </button>
              <button type="button" onClick={() => setDialog('out')} className="btn btn-secondary btn-sm">
                <ArrowUpFromLine className="h-4 w-4" /><span>Cash out</span>
              </button>
              <button type="button" onClick={() => setDialog('close')} className="btn btn-primary btn-sm">
                <Lock className="h-4 w-4" /><span>Close shift</span>
              </button>
            </span>
          </>
        ) : (
          <>
            <span className="flex items-center gap-2">
              <Wallet className="h-4 w-4" />
              No cash shift open. Card and digital payments work; open a shift to take cash.
            </span>
            <span className="flex flex-wrap gap-2">
              <button type="button" onClick={() => setDialog('history')} className="btn btn-secondary btn-sm">My shifts</button>
              <button type="button" onClick={() => setDialog('return')} className="btn btn-secondary btn-sm">
                <Undo2 className="h-4 w-4" /><span>Return / exchange</span>
              </button>
              <button type="button" onClick={() => setDialog('open')} className="btn btn-primary btn-sm">Open shift</button>
            </span>
          </>
        )}
      </div>

      {dialog === 'history' && state.currentUser && (
        <div className="modal-overlay" role="dialog" aria-modal="true" aria-label="My shifts">
          <ModalShell className="modal max-w-6xl w-full">
            <div className="modal-header">
              <h2 className="font-bold text-lg">My shifts</h2>
              <button type="button" className="btn btn-secondary btn-sm" onClick={() => setDialog(null)}>Close</button>
            </div>
            <div className="modal-body max-h-[75vh] overflow-y-auto">
              <ShiftHistory userId={state.currentUser.id} currency={currency} personal />
            </div>
          </ModalShell>
        </div>
      )}
      {dialog === 'open' && (
        <AmountDialog
          title="Open cash shift"
          label="Opening float (cash in the drawer now)"
          confirm="Open shift"
          allowZero
          onClose={() => setDialog(null)}
          onSubmit={async amount => { refresh(await shiftsService.open(amount)); }}
        />
      )}
      {(dialog === 'in' || dialog === 'out') && (
        <AmountDialog
          title={dialog === 'in' ? 'Cash in' : 'Cash out'}
          label={dialog === 'in' ? 'Amount put into the drawer' : 'Amount taken out of the drawer'}
          confirm="Save"
          withReason
          onClose={() => setDialog(null)}
          onSubmit={async (amount, reason) => { refresh(await shiftsService.move(dialog === 'in' ? amount : -amount, reason!)); }}
        />
      )}
      {dialog === 'close' && shift && (
        <CloseShiftDialog
          shift={shift}
          money={money}
          onClose={() => setDialog(null)}
          onClosed={result => { setClosed(result); refresh(null); setDialog(null); }}
        />
      )}
      <ReturnModal isOpen={dialog === 'return'} onClose={() => setDialog(null)} />
      {closed && <ShiftReport shift={closed} money={money} onClose={() => setClosed(null)} />}
    </>
  );
}

function AmountDialog({ title, label, confirm, allowZero, withReason, onClose, onSubmit }: {
  title: string;
  label: string;
  confirm: string;
  allowZero?: boolean;
  withReason?: boolean;
  onClose: () => void;
  onSubmit: (amount: number, reason?: string) => Promise<void>;
}) {
  const [amount, setAmount] = useState('');
  const [reason, setReason] = useState('');
  const [saving, setSaving] = useState(false);
  const value = Number(amount);
  const valid = amount !== '' && Number.isFinite(value) && (allowZero ? value >= 0 : value > 0) && (!withReason || reason.trim());

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!valid) return;
    setSaving(true);
    try {
      await onSubmit(Math.round(value * 100) / 100, reason.trim() || undefined);
      onClose();
    } catch (error) {
      swalConfig.error(getErrorMessage(error));
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="modal-overlay">
      <ModalShell className="modal max-w-sm">
        <div className="modal-header">
          <h2 className="text-lg font-bold text-link">{title}</h2>
          <button onClick={onClose} className="text-bodytext hover:text-bodytext p-2"><X className="h-5 w-5" /></button>
        </div>
        <form onSubmit={submit}>
          <div className="modal-body space-y-4">
            <label className="block">
              <span className="block text-sm font-medium text-link mb-1">{label}</span>
              <Input type="number" min="0" step="0.01" value={amount} onChange={e => setAmount(e.target.value)} className="input" autoFocus />
            </label>
            {withReason && (
              <label className="block">
                <span className="block text-sm font-medium text-link mb-1">Reason</span>
                <Input value={reason} onChange={e => setReason(e.target.value)} className="input" placeholder="e.g. Bank deposit, change from bank" />
              </label>
            )}
          </div>
          <div className="modal-footer">
            <button type="button" onClick={onClose} className="btn btn-secondary btn-md">Cancel</button>
            <button type="submit" className="btn btn-primary btn-md" disabled={!valid || saving}>{saving ? 'Saving…' : confirm}</button>
          </div>
        </form>
      </ModalShell>
    </div>
  );
}

function ShiftLines({ shift, money }: { shift: CashShift; money: (n: number) => string }) {
  const rows: [string, number][] = [
    ['Opening float', shift.openingFloat],
    ['Cash sales', shift.cashSales],
    ['Cash refunds', -shift.cashRefunds],
    ['Cash in', shift.cashIn],
    ['Cash out', -shift.cashOut],
  ];
  const tenders = Object.entries(shift.otherPayments);
  return (
    <div className="space-y-3">
      <DataTable className="w-full text-sm">
        <tbody>
          {rows.map(([label, value]) => (
            <tr key={label}><td className="py-1 text-bodytext">{label}</td><td className="py-1 text-right">{money(value)}</td></tr>
          ))}
          <tr className="border-t font-semibold">
            <td className="py-1">Expected cash in drawer</td><td className="py-1 text-right">{money(shift.expectedCash)}</td>
          </tr>
        </tbody>
      </DataTable>
      {tenders.length > 0 && (
        <div>
          <p className="text-xs font-semibold text-bodytext uppercase mb-1">Other payments this shift (not in the drawer)</p>
          <DataTable className="w-full text-sm">
            <tbody>
              {tenders.map(([method, value]) => (
                <tr key={method}><td className="py-0.5 capitalize text-bodytext">{method}</td><td className="py-0.5 text-right">{money(value)}</td></tr>
              ))}
            </tbody>
          </DataTable>
        </div>
      )}
    </div>
  );
}

function CloseShiftDialog({ shift, money, onClose, onClosed }: {
  shift: CashShift;
  money: (n: number) => string;
  onClose: () => void;
  onClosed: (shift: CashShift) => void;
}) {
  const [counted, setCounted] = useState('');
  const [notes, setNotes] = useState('');
  const [saving, setSaving] = useState(false);
  const value = Number(counted);
  const hasCount = counted !== '' && Number.isFinite(value) && value >= 0;
  const variance = hasCount ? Math.round((value - shift.expectedCash) * 100) / 100 : 0;

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!hasCount) return;
    if (variance !== 0 && !notes.trim()) {
      swalConfig.error('The count differs from the expected cash; add a note');
      return;
    }
    setSaving(true);
    try {
      onClosed(await shiftsService.close(value, notes.trim() || undefined));
    } catch (error) {
      swalConfig.error(getErrorMessage(error));
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="modal-overlay">
      <ModalShell className="modal max-w-md">
        <div className="modal-header">
          <h2 className="text-lg font-bold text-link">Close {shift.sessionNo}</h2>
          <button onClick={onClose} className="text-bodytext hover:text-bodytext p-2"><X className="h-5 w-5" /></button>
        </div>
        <form onSubmit={submit}>
          <div className="modal-body space-y-4">
            <ShiftLines shift={shift} money={money} />
            <label className="block">
              <span className="block text-sm font-medium text-link mb-1">Counted cash in the drawer</span>
              <Input type="number" min="0" step="0.01" value={counted} onChange={e => setCounted(e.target.value)} className="input" autoFocus />
            </label>
            {hasCount && (
              <p className={`text-sm font-semibold ${variance === 0 ? 'text-success' : 'text-error'}`}>
                {variance === 0 ? 'Drawer balances' : `${variance > 0 ? 'Over' : 'Short'} by ${money(Math.abs(variance))}`}
              </p>
            )}
            <label className="block">
              <span className="block text-sm font-medium text-link mb-1">Notes {variance !== 0 ? '(required)' : '(optional)'}</span>
              <Input value={notes} onChange={e => setNotes(e.target.value)} className="input" />
            </label>
          </div>
          <div className="modal-footer">
            <button type="button" onClick={onClose} className="btn btn-secondary btn-md">Cancel</button>
            <button type="submit" className="btn btn-primary btn-md" disabled={!hasCount || saving}>
              {saving ? 'Closing…' : 'Close shift'}
            </button>
          </div>
        </form>
      </ModalShell>
    </div>
  );
}

function ShiftReport({ shift, money, onClose }: { shift: CashShift; money: (n: number) => string; onClose: () => void }) {
  return (
    <div className="modal-overlay">
      <ModalShell className="modal max-w-md">
        <div className="modal-header">
          <h2 className="text-lg font-bold text-link">{shift.sessionNo} closed</h2>
          <button onClick={onClose} className="text-bodytext hover:text-bodytext p-2"><X className="h-5 w-5" /></button>
        </div>
        <div className="modal-body space-y-4" id="shift-report">
          <p className="text-sm text-bodytext">
            {shift.openedAt.toLocaleString()} – {shift.closedAt?.toLocaleString()}
          </p>
          <ShiftLines shift={shift} money={money} />
          <DataTable className="w-full text-sm">
            <tbody>
              <tr><td className="py-1 text-bodytext">Counted</td><td className="py-1 text-right">{money(shift.countedCash ?? 0)}</td></tr>
              <tr className="font-semibold">
                <td className="py-1">Variance</td>
                <td className={`py-1 text-right ${shift.variance ? 'text-error' : 'text-success'}`}>{money(shift.variance ?? 0)}</td>
              </tr>
            </tbody>
          </DataTable>
        </div>
        <div className="modal-footer">
          <button type="button" onClick={() => window.print()} className="btn btn-secondary btn-md">Print</button>
          <button type="button" onClick={onClose} className="btn btn-primary btn-md">Done</button>
        </div>
      </ModalShell>
    </div>
  );
}
