import {Input}from'@/components/ui/input';
import { useState, type FormEvent } from 'react';
import { shiftsService, type ShiftHistoryRow } from '../../lib/services';
import { getErrorMessage } from '../../lib/errors';
import { swalConfig } from '../../lib/sweetAlert';

export function ForceCloseModal({
  shift,
  onClose,
}: {
  shift: ShiftHistoryRow;
  onClose: () => void;
}) {
  const [requestId] = useState(() => crypto.randomUUID());
  const [counted, setCounted] = useState('');
  const [notes, setNotes] = useState('');
  const [saving, setSaving] = useState(false);
  const valid =
    counted.trim() !== '' &&
    Number.isFinite(Number(counted)) &&
    Number(counted) >= 0 &&
    notes.trim() !== '';
  async function submit(event: FormEvent) {
    event.preventDefault();
    if (!valid || saving) return;
    setSaving(true);
    try {
      await shiftsService.forceClose(
        shift.id,
        Number(counted),
        notes.trim(),
        requestId,
      );
      onClose();
    } catch (err) {
      swalConfig.error(getErrorMessage(err));
    } finally {
      setSaving(false);
    }
  }
  return (
    <div
      className="modal-overlay"
      role="dialog"
      aria-modal="true"
      aria-label="Close for cashier"
    >
      <form className="modal max-w-md" onSubmit={submit}>
        <div className="modal-header">
          <h2 className="text-lg font-bold">Close for cashier</h2>
        </div>
        <div className="modal-body space-y-4">
          <p>
            {shift.session_no} · {shift.user_name}
          </p>
          <p className="text-sm text-bodytext">
            Count the drawer before closing. Your name and these notes will be
            recorded.
          </p>
          <label className="block">
            Counted cash
            <Input
              className="input block"
              type="number"
              min="0"
              step="0.01"
              required
              value={counted}
              onChange={(e) => setCounted(e.target.value)}
            />
          </label>
          <label className="block">
            Closing notes
            <textarea
              className="textarea block w-full"
              required
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
            />
          </label>
        </div>
        <div className="modal-footer">
          <button
            type="button"
            className="btn btn-secondary btn-md"
            disabled={saving}
            onClick={onClose}
          >
            Cancel
          </button>
          <button
            type="submit"
            className="btn btn-primary btn-md"
            disabled={!valid || saving}
          >
            {saving ? 'Closing…' : 'Close for cashier'}
          </button>
        </div>
      </form>
    </div>
  );
}
