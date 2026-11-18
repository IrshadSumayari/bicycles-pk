import { useBusinessLookups } from '../../lib/lookups';
import {Input}from'@/components/ui/input';
import {ModalShell}from'@/components/shared/ModalShell';
import React, { useEffect, useState } from 'react';
import { X } from 'lucide-react';
import { Product, productLabel } from '../../types';
import { productsService } from '../../lib/services';
import { swalConfig } from '../../lib/sweetAlert';
import { getErrorMessage } from '../../lib/errors';
import { DEFAULT_REASONS, stockReasons } from '../../lib/stockReasons';

interface StockAdjustModalProps {
  product: Product | null;
  onClose: () => void;
}


// Every stock change is posted to the ledger with a reason.
export function StockAdjustModal({ product, onClose }: StockAdjustModalProps) {
  const lookup = useBusinessLookups(!!product);
  const [change, setChange] = useState('');
  const reasons = stockReasons(lookup.data?.stock_reason);
  const [reason, setReason] = useState(DEFAULT_REASONS[0]);
  const [note, setNote] = useState('');
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    setChange('');
    setReason(DEFAULT_REASONS[0]);
    setNote('');
  }, [product]);

  if (!product) return null;

  const unit = product.kind === 'pack' ? 'packs' : 'pcs';
  const amount = Number(change);
  const needsNote = reason === 'Other' && !note.trim();
  const valid = change !== '' && Number.isFinite(amount) && amount !== 0 && Number.isInteger(amount) && !needsNote;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!valid) return;
    setSaving(true);
    try {
      await productsService.adjustStock(product.id, amount, note.trim() ? `${reason}: ${note.trim()}` : reason);
      swalConfig.success('Stock updated');
      onClose();
    } catch (error) {
      swalConfig.error(`Could not update stock: ${getErrorMessage(error)}`);
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="modal-overlay">
      <ModalShell className="modal max-w-md">
        <div className="modal-header">
          <h2 className="text-lg font-bold text-link">Adjust stock</h2>
          <button onClick={onClose} className="text-bodytext hover:text-bodytext p-2 rounded-xl hover:bg-lightgray">
            <X className="h-5 w-5" />
          </button>
        </div>
        <form onSubmit={handleSubmit}>
          <div className="modal-body space-y-4">
            <div>
              <p className="font-semibold text-link">{productLabel(product)}</p>
              <p className="text-sm text-bodytext">{product.sku} · available now: {product.stock} {unit}</p>
            </div>
            <label className="block">
              <span className="block text-sm font-medium text-link mb-1">Change by ({unit})</span>
              <Input type="number" step="1" value={change} onChange={e => setChange(e.target.value)}
                     className="input" placeholder="e.g. 5 to add, -2 to remove" autoFocus />
            </label>
            <label className="block">
              <span className="block text-sm font-medium text-link mb-1">Reason</span>
              <select value={reason} onChange={e => setReason(e.target.value)} className="select">
                {reasons.map(r => <option key={r} value={r}>{r}</option>)}
              </select>
            </label>
            <label className="block">
              <span className="block text-sm font-medium text-link mb-1">Note {reason === 'Other' ? '*' : '(optional)'}</span>
              <Input value={note} onChange={e => setNote(e.target.value)} className="input" placeholder={reason === 'Other' ? 'Describe the reason' : undefined} />
              {needsNote && <span className="block text-xs text-bodytext mt-1">Write a short note to use Other, or choose a reason above.</span>}
            </label>
          </div>
          <div className="modal-footer">
            <button type="button" onClick={onClose} className="btn btn-secondary btn-md" disabled={saving}>Cancel</button>
            <button type="submit" className="btn btn-primary btn-md" disabled={saving || !valid}>
              {saving ? 'Saving...' : 'Update stock'}
            </button>
          </div>
        </form>
      </ModalShell>
    </div>
  );
}
