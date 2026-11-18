import { useBusinessLookups } from '../../lib/lookups';
import {Input}from'@/components/ui/input';
import {ModalShell}from'@/components/shared/ModalShell';
import React, { useState, useEffect } from 'react';
import { X } from 'lucide-react';
import { Customer } from '../../types';
import { useApp } from '../../context/SupabaseAppContext';
import { getErrorMessage } from '../../lib/errors';
import { swalConfig } from '../../lib/sweetAlert';
import { describeOffer, discountCodesService, formatCodeDate } from '../../lib/discountCodes';
import { CustomerCodes } from '../discounts/CustomerCodes';

interface CustomerModalProps {
  isOpen: boolean;
  onClose: () => void;
  customer: Customer | null;
  onSaved?: (customer: Customer) => void;
}

export function CustomerModal({ isOpen, onClose, customer, onSaved }: CustomerModalProps) {
  const { state, dispatch } = useApp();
  const customerLookups = useBusinessLookups(isOpen);
  const customerTiers = ['Standard', ...(customerLookups.data?.customer_tier || [])];
  const [saving, setSaving] = useState(false);
  const [emailConsent, setEmailConsent] = useState('unknown');
  const [smsConsent, setSmsConsent] = useState('unknown');
  const manager = ['admin', 'manager'].includes(state.currentUser?.role ?? '');
  const [formData, setFormData] = useState({
    name: '',
    email: '',
    phone: '',
    address: '',
    creditLimit: '',
    priceTier: 'Standard',
  });

  useEffect(() => {
    setEmailConsent(customer?.emailMarketingConsent == null ? 'unknown' : String(customer.emailMarketingConsent));
    setSmsConsent(customer?.smsMarketingConsent == null ? 'unknown' : String(customer.smsMarketingConsent));
    if (customer) {
      setFormData({
        name: customer.name,
        email: customer.email,
        phone: customer.phone,
        address: customer.address,
        creditLimit: customer.creditLimit.toString(),
        priceTier: customer.priceTier,
      });
    } else {
      setFormData({
        name: '',
        email: '',
        phone: '',
        address: '',
        creditLimit: '0',
        priceTier: 'Standard',
      });
    }
  }, [customer, isOpen]);

  if (!isOpen) return null;

  const handleSubmit = async () => {
    if (saving) return;
    // Validate required fields
    if (!formData.name.trim()) {
      swalConfig.warning('Please enter customer name');
      return;
    }

    if (!formData.email.trim() && !formData.phone.trim()) {
      swalConfig.warning('Enter a phone number or email so this customer can be found again'); return;
    }
    if (formData.email.trim() && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(formData.email.trim())) {
      swalConfig.warning('Please enter a valid email address'); return;
    }
    if (emailConsent === 'true' && !formData.email.trim()) {
      swalConfig.warning('Add an email address before recording email permission'); return;
    }
    if (smsConsent === 'true' && !formData.phone.trim()) {
      swalConfig.warning('Add a phone number before recording SMS permission'); return;
    }

    const customerData: Customer = {
      id: customer?.id || Date.now().toString(),
      name: formData.name.trim(),
      email: formData.email.trim(),
      phone: formData.phone.trim(),
      address: formData.address,
      emailMarketingConsent: emailConsent === 'unknown' ? null : emailConsent === 'true',
      smsMarketingConsent: smsConsent === 'unknown' ? null : smsConsent === 'true',
      creditLimit: manager ? parseFloat(formData.creditLimit) || 0 : 0,
      creditUsed: customer?.creditUsed || 0,
      priceTier: formData.priceTier,
      totalPurchases: customer?.totalPurchases || 0,
      lastPurchase: customer?.lastPurchase,
      createdAt: customer?.createdAt || new Date(),
    };

    setSaving(true);
    try {
      swalConfig.loading(`${customer ? 'Updating' : 'Creating'} customer...`);
      const { customersService } = await import('../../lib/services');
      
      if (customer) {
        const saved = await customersService.update(customerData.id, customerData);
        if (state.selectedCustomer?.id === saved.id) dispatch({ type: 'SET_SELECTED_CUSTOMER', payload: saved });
        onSaved?.(saved);
        swalConfig.success('Customer updated successfully!');
      } else {
        const saved = await customersService.create(customerData);
        onSaved?.(saved);
        const welcome = await discountCodesService.forCustomer(saved.id).then(c => c.find(x => x.kind === 'welcome'), () => undefined);
        if (welcome) {
          swalConfig.info(`Customer added. Their welcome code is ${welcome.code}: ${describeOffer(welcome, state.settings.currency)}, until ${formatCodeDate(welcome.expires_at)}.`);
        } else {
          swalConfig.success('Customer created successfully!');
        }
      }
      
      onClose();
    } catch (error) {
      console.error('Error saving customer:', error);
      swalConfig.error(getErrorMessage(error));
    } finally { setSaving(false); }
  };

  const handleChange = (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement>) => {
    const { name, value } = e.target;
    if (name === 'email') setEmailConsent('unknown');
    if (name === 'phone') setSmsConsent('unknown');
    setFormData(prev => ({
      ...prev,
      [name]: value
    }));
  };

  return (
    <div className="modal-overlay">
      <ModalShell className="modal max-w-md">
        <div className="modal-header">
          <h2 className="text-xl font-bold text-link">
            {customer ? 'Edit Customer' : 'Add New Customer'}
          </h2>
          <button
            onClick={onClose}
            className="text-bodytext hover:text-bodytext p-2 rounded-xl hover:bg-lightgray transition-colors"
          >
            <X className="h-6 w-6" />
          </button>
        </div>

        <div className="modal-body space-y-4">
          <div>
            <label className="block text-sm font-medium text-link mb-2">
              Full Name *
            </label>
            <Input
              type="text"
              name="name"
              value={formData.name}
              onChange={handleChange}
              className="input"
              placeholder="Enter full name"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-link mb-2">
              Email Address (optional)
            </label>
            <Input
              type="email"
              name="email"
              value={formData.email}
              onChange={handleChange}
              className="input"
              placeholder="Enter email address"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-link mb-2">
              Phone Number (or email required)
            </label>
            <Input
              type="tel"
              name="phone"
              value={formData.phone}
              onChange={handleChange}
              className="input"
              placeholder="Enter phone number"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-link mb-2">
              Address
            </label>
            <textarea
              name="address"
              value={formData.address}
              onChange={handleChange}
              rows={3}
              className="textarea"
              placeholder="Enter address"
            />
          </div>

          <fieldset className="border border-border rounded-xl p-4 space-y-3" disabled={saving}>
            <legend className="font-semibold">Promotional preferences</legend>
            <p className="text-sm text-bodytext">Ask the customer separately for each channel. Saving their details does not subscribe them. Changing contact details requires fresh permission.</p>
            <label className="block">Email offers<select aria-label="Email offers" className="select" value={emailConsent} onChange={e => setEmailConsent(e.target.value)}><option value="unknown">Not asked</option><option value="true">Customer agreed</option><option value="false">Declined / unsubscribed</option></select></label>
            <label className="block">SMS offers<select aria-label="SMS offers" className="select" value={smsConsent} onChange={e => setSmsConsent(e.target.value)}><option value="unknown">Not asked</option><option value="true">Customer agreed</option><option value="false">Declined / unsubscribed</option></select></label>
            {customer && <p className="text-xs text-bodytext">When changing an email or phone, save the new contact first, then reopen to record permission for it.</p>}
          </fieldset>
          {customer && <CustomerCodes customer={customer} />}
          <div>
            <label className="block text-sm font-medium text-link mb-2">
              Credit Limit
            </label>
            <Input
              type="number"
              step="0.01"
              min="0"
              disabled={!manager}
              name="creditLimit"
              value={formData.creditLimit}
              onChange={handleChange}
              className="input"
              placeholder="0.00"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-link mb-2">
              Price Tier
            </label>
            <select
              disabled={!manager}
              name="priceTier"
              value={formData.priceTier}
              onChange={handleChange}
              className="select"
            >
              {!customerTiers.includes(formData.priceTier) && <option value={formData.priceTier}>{formData.priceTier} (current value)</option>}
              {customerTiers.map(tier => <option key={tier} value={tier}>{tier}</option>)}
            </select>
          </div>
        </div>

        <div className="modal-footer">
          <button
            type="button"
            onClick={onClose}
            className="btn btn-secondary btn-md"
          >
            Cancel
          </button>
          <button
            type="button"
            disabled={saving}
            onClick={handleSubmit}
            className="btn btn-primary btn-md"
          >
            {saving ? 'Saving...' : customer ? 'Update Customer' : 'Add Customer'}
          </button>
        </div>
      </ModalShell>
    </div>
  );
}