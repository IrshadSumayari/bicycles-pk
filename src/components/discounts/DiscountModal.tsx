import { useBusinessLookups } from '../../lib/lookups';
import {Input}from'@/components/ui/input';
import {ModalShell}from'@/components/shared/ModalShell';
import { ProductPicker } from '../inventory/ProductPicker';
import React, { useState, useEffect } from 'react';
import { X, Plus, Trash2 } from 'lucide-react';
import { Discount, DiscountCondition } from '../../types';
import { useApp } from '../../context/SupabaseAppContext';
import { swalConfig } from '../../lib/sweetAlert';

interface DiscountModalProps {
  isOpen: boolean;
  onClose: () => void;
  discount: Discount | null;
}

export function DiscountModal({ isOpen, onClose, discount }: DiscountModalProps) {
  const { state } = useApp();
  const bankLookup = useBusinessLookups(isOpen);
  const bankNames = bankLookup.data?.bank || [];
  const customerTiers = ['Standard', ...(bankLookup.data?.customer_tier || [])];
  const [formData, setFormData] = useState({
    name: '',
    description: '',
    type: 'percentage' as 'percentage' | 'fixed' | 'free_gift',
    value: '',
    minAmount: '',
    maxDiscount: '',
    validFrom: '',
    validTo: '',
    active: true,
  });
  const [conditions, setConditions] = useState<DiscountCondition[]>([]);
  const [freeGiftProducts, setFreeGiftProducts] = useState<string[]>([]);
  const [validDays, setValidDays] = useState<number[]>([]);

  useEffect(() => {
    if (discount) {
      setFormData({
        name: discount.name,
        description: discount.description,
        type: discount.type === 'bogo' ? 'percentage' : discount.type,
        value: discount.value.toString(),
        minAmount: discount.minAmount?.toString() || '',
        maxDiscount: discount.maxDiscount?.toString() || '',
        validFrom: discount.validFrom.toISOString().split('T')[0],
        validTo: discount.validTo.toISOString().split('T')[0],
        active: discount.active,
      });
      setConditions((discount.conditions || []).map(condition => 
        condition.type === 'specific_products' && !condition.minQuantity 
          ? { ...condition, minQuantity: 1 }
          : condition
      ));
      setFreeGiftProducts(discount.freeGiftProducts || []);
      setValidDays(discount.validDays || []);
    } else {
      setFormData({
        name: '',
        description: '',
        type: 'percentage',
        value: '',
        minAmount: '',
        maxDiscount: '',
        validFrom: new Date().toISOString().split('T')[0],
        validTo: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString().split('T')[0],
        active: true,
      });
      setConditions([]);
      setFreeGiftProducts([]);
      setValidDays([]);
    }
  }, [discount]);

  if (!isOpen) return null;

  const handleSubmit = async () => {
    // Validate required fields
    if (!formData.name.trim()) {
      swalConfig.warning('Please enter a discount name');
      return;
    }

    if (formData.type !== 'free_gift' && (!formData.value || parseFloat(formData.value) <= 0)) {
      swalConfig.warning('Please enter a valid discount value');
      return;
    }

    if (!formData.validFrom || !formData.validTo) {
      swalConfig.warning('Please select valid dates');
      return;
    }

    // Validate specific products conditions
    const specificProductsConditions = conditions.filter(c => c.type === 'specific_products');
    for (const condition of specificProductsConditions) {
      if (!condition.value || (Array.isArray(condition.value) && condition.value.length === 0)) {
        swalConfig.warning('Please select at least one product for specific products conditions');
        return;
      }
      if (!condition.minQuantity || condition.minQuantity < 1) {
        swalConfig.warning('Minimum quantity must be at least 1 for specific products conditions');
        return;
      }
    }

    // Validate card-specific conditions
    const hasCardTypeCondition = conditions.some(c => c.type === 'card_type');
    const hasBankNameCondition = conditions.some(c => c.type === 'bank_name');
    const paymentMethodCondition = conditions.find(c => c.type === 'payment_method');
    
    if ((hasCardTypeCondition || hasBankNameCondition) && paymentMethodCondition && paymentMethodCondition.value !== 'card') {
      swalConfig.warning('Card Type and Bank Name conditions can only be used with Card payment method. Please remove the conflicting payment method condition or change it to "Card".');
      return;
    }

    if ((hasCardTypeCondition || hasBankNameCondition) && !paymentMethodCondition) {
      const result = await swalConfig.confirm(
        'Card Payment Condition Warning',
        'You have Card Type or Bank Name conditions but no Payment Method condition. These conditions will only apply when customers pay with cards. Do you want to continue?',
        'Continue'
      );
      if (!result.isConfirmed) return;
    }

    const discountData: Discount = {
      id: discount?.id || Date.now().toString(),
      name: formData.name,
      description: formData.description,
      type: formData.type,
      value: formData.type === 'free_gift' ? 0 : parseFloat(formData.value),
      conditions,
      freeGiftProducts: formData.type === 'free_gift' ? freeGiftProducts : undefined,
      minAmount: formData.minAmount ? parseFloat(formData.minAmount) : undefined,
      maxDiscount: formData.maxDiscount ? parseFloat(formData.maxDiscount) : undefined,
      validFrom: new Date(formData.validFrom),
      validTo: new Date(formData.validTo),
      validDays: validDays.length > 0 ? validDays : undefined,
      active: formData.active,
      createdAt: discount?.createdAt || new Date(),
    };

    try {
      swalConfig.loading(`${discount ? 'Updating' : 'Creating'} discount...`);
      const { discountsService } = await import('../../lib/services');
      
      if (discount) {
        await discountsService.update(discount.id, discountData);
        swalConfig.success('Discount updated successfully!');
      } else {
        await discountsService.create(discountData);
        swalConfig.success('Discount created successfully!');
      }
      
      onClose();
    } catch (error) {
      console.error('Error saving discount:', error);
      swalConfig.error('Failed to save discount. Please try again.');
    }
  };

  const handleChange = (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement>) => {
    const { name, value, type } = e.target;
    setFormData(prev => ({
      ...prev,
      [name]: type === 'checkbox' ? (e.target as HTMLInputElement).checked : value
    }));
  };

  const addCondition = () => {
    setConditions(prev => [...prev, {
      type: 'min_amount',
      value: '',
      operator: 'greater_than'
    }]);
  };

  const updateCondition = (index: number, field: keyof DiscountCondition, value: DiscountCondition[keyof DiscountCondition]) => {
    setConditions(prev => prev.map((condition, i) => {
      if (i === index) {
        const updatedCondition = { ...condition, [field]: value };
        
        // Set default minQuantity when switching to specific_products type
        if (field === 'type' && value === 'specific_products' && !updatedCondition.minQuantity) {
          updatedCondition.minQuantity = 1;
        }
        
        return updatedCondition;
      }
      return condition;
    }));
  };

  const removeCondition = (index: number) => {
    setConditions(prev => prev.filter((_, i) => i !== index));
  };

  const toggleDay = (day: number) => {
    setValidDays(prev => 
      prev.includes(day) 
        ? prev.filter(d => d !== day)
        : [...prev, day].sort()
    );
  };


  const dayNames = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

  // Helper function to check for card-specific conditions
  const getCardConditionWarning = () => {
    const hasCardTypeCondition = conditions.some(c => c.type === 'card_type');
    const hasBankNameCondition = conditions.some(c => c.type === 'bank_name');
    const paymentMethodCondition = conditions.find(c => c.type === 'payment_method');
    
    if (hasCardTypeCondition || hasBankNameCondition) {
      if (paymentMethodCondition && paymentMethodCondition.value !== 'card') {
        return {
          type: 'error',
          message: 'Conflicting conditions: Card Type/Bank Name conditions require Card payment method.'
        };
      } else if (!paymentMethodCondition) {
        return {
          type: 'warning',
          message: 'Card Type/Bank Name conditions will only apply when customers pay with cards.'
        };
      } else if (paymentMethodCondition.value === 'card') {
        return {
          type: 'info',
          message: 'Great! Card-specific conditions are properly configured with Card payment method.'
        };
      }
    }
    return null;
  };

  const cardConditionWarning = getCardConditionWarning();

  return (
    <div className="modal-overlay">
      <ModalShell className="modal max-w-4xl">
        <div className="modal-header">
          <h2 className="text-xl font-bold text-link">
            {discount ? 'Edit Discount' : 'Add New Discount'}
          </h2>
          <button
            onClick={onClose}
            className="text-bodytext hover:text-bodytext p-2 rounded-xl hover:bg-lightgray transition-colors"
          >
            <X className="h-6 w-6" />
          </button>
        </div>

        <div className="modal-body space-y-6">
          {/* Basic Information */}
          <div>
            <h3 className="text-lg font-semibold text-link mb-4">Basic Information</h3>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div>
                <label className="block text-sm font-medium text-link mb-2">
                  Discount Name *
                </label>
                <Input
                  type="text"
                  name="name"
                  value={formData.name}
                  onChange={handleChange}
                  required
                  className="input"
                  placeholder="Enter discount name"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-link mb-2">
                  Discount Type *
                </label>
                <select
                  name="type"
                  value={formData.type}
                  onChange={handleChange}
                  className="select"
                >
                  <option value="percentage">Percentage Discount</option>
                  <option value="fixed">Fixed Amount Discount</option>
                  <option value="free_gift">Free Gift</option>
                </select>
              </div>
            </div>

            <div className="mt-4">
              <label className="block text-sm font-medium text-link mb-2">
                Description
              </label>
              <textarea
                name="description"
                value={formData.description}
                onChange={handleChange}
                rows={3}
                className="textarea"
                placeholder="Enter discount description"
              />
            </div>
          </div>

          {/* Discount Value */}
          <div>
            <h3 className="text-lg font-semibold text-link mb-4">Discount Value</h3>
            <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
              {formData.type !== 'free_gift' && (
                <div>
                  <label className="block text-sm font-medium text-link mb-2">
                    {formData.type === 'percentage' ? 'Percentage (%)' : `Amount (${state.settings.currency})`} *
                  </label>
                  <Input
                    type="number"
                    step="0.01"
                    min="0"
                    name="value"
                    value={formData.value}
                    onChange={handleChange}
                    required
                    className="input"
                    placeholder={formData.type === 'percentage' ? '10' : '100'}
                  />
                </div>
              )}

              <div>
                <label className="block text-sm font-medium text-link mb-2">
                  Minimum Amount ({state.settings.currency})
                </label>
                <Input
                  type="number"
                  step="0.01"
                  min="0"
                  name="minAmount"
                  value={formData.minAmount}
                  onChange={handleChange}
                  className="input"
                  placeholder="0"
                />
              </div>

              {formData.type === 'percentage' && (
                <div>
                  <label className="block text-sm font-medium text-link mb-2">
                    Maximum Discount ({state.settings.currency})
                  </label>
                  <Input
                    type="number"
                    step="0.01"
                    min="0"
                    name="maxDiscount"
                    value={formData.maxDiscount}
                    onChange={handleChange}
                    className="input"
                    placeholder="No limit"
                  />
                </div>
              )}
            </div>
          </div>

          {/* Free Gift Products */}
          {formData.type === 'free_gift' && (
            <div>
              <h3 className="text-lg font-semibold text-link mb-4">Free Gift Products</h3>
              <ProductPicker label="Search gift products" selected={freeGiftProducts} onChange={setFreeGiftProducts} />
              {freeGiftProducts.length === 0 && (
                <p className="text-sm text-bodytext mt-2">Please select at least one product for free gift</p>
              )}
            </div>
          )}

          {/* Valid Days */}
          <div>
            <h3 className="text-lg font-semibold text-link mb-4">Valid Days (Optional)</h3>
            <p className="text-sm text-bodytext mb-3">Select specific days when this discount is valid. Leave empty for all days.</p>
            <div className="grid grid-cols-7 gap-2">
              {dayNames.map((day, index) => (
                <button
                  key={index}
                  type="button"
                  onClick={() => toggleDay(index)}
                  className={`btn btn-sm transition-all ${
                    validDays.includes(index) ? 'btn-primary' : 'btn-secondary'
                  }`}
                >
                  {day.slice(0, 3)}
                </button>
              ))}
            </div>
          </div>

          {/* Conditions */}
          <div>
            <div className="flex items-center justify-between mb-4">
              <div>
                <h3 className="text-lg font-semibold text-link">Additional Conditions</h3>
                <p className="text-sm text-bodytext">Add specific conditions that must be met for this discount to apply</p>
              </div>
              <button
                type="button"
                onClick={addCondition}
                className="btn btn-primary btn-sm"
              >
                <Plus className="h-4 w-4" />
                Add Condition
              </button>
            </div>

            {/* Card Condition Warning/Info */}
            {(() => {
              const warning = getCardConditionWarning();
              if (!warning) return null;
              
              const bgColor = warning.type === 'error' ? 'bg-lighterror border-lighterror' :
                             warning.type === 'warning' ? 'bg-lightwarning border-lightwarning' :
                             'bg-lightprimary border-lightprimary';
              const textColor = warning.type === 'error' ? 'text-error' :
                               warning.type === 'warning' ? 'text-warning' :
                               'text-primary';
              const icon = warning.type === 'error' ? '⚠️' : 
                          warning.type === 'warning' ? '⚡' : 
                          '💡';
              
              return (
                <div className={`p-3 rounded-xl border ${bgColor} mb-4`}>
                  <div className={`text-sm ${textColor} flex items-center space-x-2`}>
                    <span>{icon}</span>
                    <span>{warning.message}</span>
                  </div>
                </div>
              );
            })()}

            {conditions.length > 0 && (
              <div className="space-y-4 max-h-64 overflow-y-auto">
                {conditions.map((condition, index) => (
                  <div key={index} className="card p-4 border border-border">
                    <div className={`grid gap-4 ${condition.type === 'specific_products' ? 'grid-cols-1 md:grid-cols-4' : 'grid-cols-1 md:grid-cols-3'}`}>
                      <div>
                        <label className="block text-sm font-medium text-link mb-2">
                          Condition Type
                        </label>
                        <select
                          value={condition.type}
                          onChange={(e) => updateCondition(index, 'type', e.target.value)}
                          className="select"
                        >
                          <option value="min_amount">Minimum Amount</option>
                          <option value="specific_products">Specific Products</option>
                          <option value="payment_method">Payment Method</option>
                          <option value="customer_tier">Customer Tier</option>
                          <option value="card_type">Card Type (Card Payments)</option>
                          <option value="bank_name">Bank Name (Card Payments)</option>
                        </select>
                      </div>

                      <div className={condition.type === 'specific_products' ? 'md:col-span-2' : ''}>
                        <label className="block text-sm font-medium text-link mb-2">
                          {condition.type === 'specific_products' ? 'Products & Minimum Quantity' : 'Value'}
                        </label>
                        {condition.type === 'specific_products' ? (
                          <div className="space-y-3">
                            <div className="border border-border rounded-lg p-3 bg-lightgray">
                              <label className="block text-xs font-medium text-link mb-2">
                                Select Products
                              </label>
                              <ProductPicker label={`Search condition products ${index + 1}`} selected={Array.isArray(condition.value) ? condition.value : []} onChange={ids => updateCondition(index, 'value', ids)} />
                            </div>
                            <div className="mt-3">
                              <label className="block text-xs font-medium text-link mb-1">
                                Minimum Quantity Required
                              </label>
                              <Input
                                type="number"
                                min="1"
                                value={condition.minQuantity || 1}
                                onChange={(e) => updateCondition(index, 'minQuantity', parseInt(e.target.value) || 1)}
                                className="input"
                                placeholder="1"
                              />
                            </div>
                            <p className="text-xs text-primary mt-2">
                              💡 Customer must purchase at least {condition.minQuantity || 1} of any selected product(s)

                            </p>
                          </div>
                        ) : condition.type === 'payment_method' ? (
                          <select
                            value={condition.value}
                            onChange={(e) => updateCondition(index, 'value', e.target.value)}
                            className="select"
                          >
                            <option value="">Select Payment Method</option>
                            <option value="cash">Cash</option>
                            <option value="card">Card</option>
                            <option value="digital">Digital</option>
                            <option value="credit">Credit</option>
                          </select>
                        ) : condition.type === 'customer_tier' ? (
                          <select
                            value={condition.value}
                            onChange={(e) => updateCondition(index, 'value', e.target.value)}
                            className="select"
                          >
                            <option value="">Select Tier</option>
                            {typeof condition.value === 'string' && condition.value && !customerTiers.includes(condition.value) && <option value={condition.value}>{condition.value} (current value)</option>}
                            {customerTiers.map(tier => <option key={tier} value={tier}>{tier}</option>)}
                          </select>
                        ) : condition.type === 'card_type' ? (
                          <div>
                            <select
                              value={condition.value}
                              onChange={(e) => updateCondition(index, 'value', e.target.value)}
                              className="select"
                            >
                              <option value="">Select Card Type</option>
                              <option value="visa">Visa</option>
                              <option value="mastercard">Mastercard</option>
                              <option value="amex">American Express</option>
                              <option value="discover">Discover</option>
                            </select>
                            <p className="text-xs text-primary mt-1">
                              💡 This condition only applies when payment method is 'Card'
                            </p>
                          </div>
                        ) : condition.type === 'bank_name' ? (
                          <div>
                            <select
                              value={condition.value}
                              onChange={(e) => updateCondition(index, 'value', e.target.value)}
                              className="select"
                            >
                              <option value="">Select Bank</option>
                              {typeof condition.value === 'string' && condition.value && !bankNames.includes(condition.value) && <option value={condition.value}>{condition.value} (current value)</option>}
                              {bankNames.map(bank => <option key={bank} value={bank}>{bank}</option>)}
                            </select>
                            <p className="text-xs text-primary mt-1">
                              💡 This condition only applies when payment method is 'Card'
                            </p>
                          </div>
                        ) : (
                          <Input
                            type={condition.type === 'min_amount' ? 'number' : 'text'}
                            step={condition.type === 'min_amount' ? '0.01' : undefined}
                            min={condition.type === 'min_amount' ? '0' : undefined}
                            value={condition.value}
                            onChange={(e) => updateCondition(index, 'value', e.target.value)}
                            className="input"
                            placeholder="Enter value"
                          />
                        )}
                      </div>

                      <div className="flex items-end">
                        <button
                          type="button"
                          onClick={() => removeCondition(index)}
                          className="btn btn-danger btn-sm w-full"
                        >
                          <Trash2 className="h-4 w-4" />
                          Remove
                        </button>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>

          {/* Validity Period */}
          <div>
            <h3 className="text-lg font-semibold text-link mb-4">Validity Period</h3>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div>
                <label className="block text-sm font-medium text-link mb-2">
                  Valid From *
                </label>
                <Input
                  type="date"
                  name="validFrom"
                  value={formData.validFrom}
                  onChange={handleChange}
                  required
                  className="input"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-link mb-2">
                  Valid To *
                </label>
                <Input
                  type="date"
                  name="validTo"
                  value={formData.validTo}
                  onChange={handleChange}
                  required
                  className="input"
                />
              </div>
            </div>
          </div>

          {/* Status */}
          <div className="border-t border-border pt-6">
            <label className="flex items-center space-x-3">
              <Input
                type="checkbox"
                name="active"
                checked={formData.active}
                onChange={handleChange}
                className="rounded-sm border-border text-primary focus:ring-primary h-5 w-5"
              />
              <div>
                <span className="text-sm font-medium text-link">Active</span>
                <p className="text-xs text-bodytext">Enable this discount to be automatically applied</p>
              </div>
            </label>
          </div>

          {/* Card Condition Warning */}
          {cardConditionWarning && (
            <div className={`p-4 rounded-lg ${cardConditionWarning.type === 'error' ? 'bg-lighterror border-error' : 'bg-lightwarning border-warning'} border`}>
              <p className="text-sm font-medium text-link">
                {cardConditionWarning.message}
              </p>
            </div>
          )}
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
            onClick={handleSubmit}
            className="btn btn-primary btn-md"
          >
            {discount ? 'Update Discount' : 'Add Discount'}
          </button>
        </div>
      </ModalShell>
    </div>
  );
}
