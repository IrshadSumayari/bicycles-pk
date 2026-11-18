import { CustomerModal } from '../customers/CustomerModal';
import {Input}from'@/components/ui/input';
import { useCustomerSearch } from '../../lib/hooks/useCustomers';
import { getErrorMessage } from '../../lib/errors';
import { useState } from 'react';
import { CustomerDetailModal } from '../customers/CustomerDetailModal';
import { Trash2, Plus, Minus, User, UserPlus, Percent, FileText, ShoppingCart } from 'lucide-react';
import { CartItem, Customer } from '../../types';
import { useApp } from '../../context/SupabaseAppContext';
import { calculateTotals, lineDiscountAmount, lineGross, roundMoney } from '../../lib/pricing';

interface CartProps {
  onCheckout: () => void;
  onSaveDraft: () => void;
}

export function Cart({ onCheckout, onSaveDraft }: CartProps) {
  const { state, dispatch } = useApp();
  const [showCustomerSearch, setShowCustomerSearch] = useState(false);
  const [showNewCustomer, setShowNewCustomer] = useState(false);
  const [showAccount, setShowAccount] = useState(false);
  const [customerSearch, setCustomerSearch] = useState('');

  const isTouchMode = state.settings.interfaceMode === 'touch';

  const updateQuantity = (index: number, newQuantity: number) => {
    if (newQuantity <= 0) {
      dispatch({ type: 'REMOVE_FROM_CART', payload: index });
    } else {
      const item = state.cart[index];
      const resized = { ...item, quantity: newQuantity };
      const gross = lineGross(resized);
      const discount = Math.min(item.discount || 0, gross);
      const updatedItem = {
        ...resized,
        discount,
        subtotal: roundMoney(gross - discount)
      };
      dispatch({ type: 'UPDATE_CART_ITEM', payload: { index, item: updatedItem } });
    }
  };

  const removeFromCart = (index: number) => {
    dispatch({ type: 'REMOVE_FROM_CART', payload: index });
  };

  const applyDiscount = (index: number, discount: number, discountType: 'percentage' | 'fixed') => {
    const item = state.cart[index];
    const discountAmount = lineDiscountAmount(item, discount, discountType);

    const updatedItem = {
      ...item,
      discount: discountAmount,
      discountType,
      subtotal: roundMoney(lineGross(item) - discountAmount)
    };

    dispatch({ type: 'UPDATE_CART_ITEM', payload: { index, item: updatedItem } });
  };

  const selectCustomer = (customer: Customer) => {
    dispatch({ type: 'SET_SELECTED_CUSTOMER', payload: customer });
    setShowCustomerSearch(false);
    setCustomerSearch('');
  };

  const customerQuery = useCustomerSearch(showCustomerSearch ? customerSearch : '');
  const filteredCustomers = customerQuery.data ?? [];

  const { subtotal, totalDiscount, taxAmount, total } = calculateTotals(state.cart, state.settings.taxRate);

  return (
    <div className={`card flex flex-col h-full shrink-0 ${
      isTouchMode ? 'w-[400px]' : 'w-[360px]'
    } max-w-full`}>
      {showNewCustomer && <CustomerModal isOpen customer={null} onClose={() => setShowNewCustomer(false)} onSaved={selectCustomer} />}
      {showAccount && state.selectedCustomer && <CustomerDetailModal customer={state.selectedCustomer} onClose={() => setShowAccount(false)} />}
      {/* Cart Header: kept compact so the item list gets the height */}
      <div className="p-3 border-b border-border flex-shrink-0 space-y-2.5">
        <div className="cart-title-row flex items-center justify-between">
          <h2 className={`font-bold text-link ${isTouchMode ? 'text-xl' : 'text-lg'}`}>
            Shopping Cart
          </h2>
          <div className="flex items-center space-x-2">
            <ShoppingCart className="h-5 w-5 text-bodytext" />
            <span className="badge badge-info">
              {state.cart.length} items
            </span>
          </div>
        </div>

        {/* Customer Selection */}
        <div className="relative">
          {state.selectedCustomer ? (
            <div className="card px-3 py-2 border-lightsuccess bg-lightsuccess">
              <div className="flex items-center justify-between gap-2">
                <div className="min-w-0 flex-1">
                  <p className={`font-medium text-success truncate ${isTouchMode ? 'text-base' : 'text-sm'}`}>
                    <button type="button" className="underline underline-offset-2" onClick={() => setShowAccount(true)} title="View customer account">{state.selectedCustomer.name}</button>
                  </p>
                  <p className={`text-success truncate ${isTouchMode ? 'text-sm' : 'text-xs'}`}>
                    {state.selectedCustomer.phone || state.selectedCustomer.email}
                  </p>
                </div>
                <button
                  onClick={() => dispatch({ type: 'SET_SELECTED_CUSTOMER', payload: null })}
                  className="text-success hover:text-success p-2 rounded-lg hover:bg-lightsuccess transition-colors flex-shrink-0"
                  aria-label="Remove customer from sale"
                  title="Remove customer from sale"
                >
                  <Trash2 className="h-4 w-4" />
                </button>
              </div>
            </div>
          ) : (
            <div className="flex gap-2">
              <button
                onClick={() => setShowCustomerSearch(!showCustomerSearch)}
                aria-expanded={showCustomerSearch}
                className={`btn btn-secondary flex-1 min-w-0 ${
                  isTouchMode ? 'btn-md touch-friendly' : 'btn-sm'
                }`}
              >
                <User className="h-4 w-4 flex-shrink-0" />
                <span className="truncate">Select Customer</span>
              </button>
              <button
                type="button"
                className={`btn btn-secondary flex-shrink-0 ${isTouchMode ? 'btn-md touch-friendly' : 'btn-sm'}`}
                onClick={() => { setShowCustomerSearch(false); setShowNewCustomer(true); }}
                title="Save a name and phone/email to link purchases and record optional offers. The customer may decline."
              >
                <UserPlus className="h-4 w-4 flex-shrink-0" />
                <span>New<span className="sr-only"> customer</span></span>
              </button>
            </div>
          )}
          {/* Customer Search Dropdown */}
          {showCustomerSearch && (
            <div className="absolute top-full left-0 right-0 mt-2 bg-card border border-border rounded-2xl shadow-lg z-50 max-h-64 overflow-hidden animate-slide-up">
              <div className="p-4">
                <Input
                  type="text"
                  placeholder="Search customers..."
                  value={customerSearch}
                  onChange={(e) => setCustomerSearch(e.target.value)}
                  className="input input-sm"
                  autoFocus
                />
              </div>
              <div className="max-h-48 overflow-y-auto">
                {customerQuery.searching && <p role="status" className="p-4 text-sm">Searching customers…</p>}
                {customerQuery.isError && <p role="alert" className="p-4 text-sm text-error">{getErrorMessage(customerQuery.error)} <button onClick={() => void customerQuery.refetch()}>Retry</button></p>}
                {filteredCustomers.map((customer) => (
                  <button
                    key={customer.id}
                    onClick={() => selectCustomer(customer)}
                    className="w-full text-left p-4 hover:bg-lightgray border-t border-border transition-colors"
                  >
                    <p className="font-medium text-sm truncate">{customer.name}</p>
                    <p className="text-xs text-bodytext truncate">{[customer.phone, customer.email].filter(Boolean).join(" · ")}</p>
                  </button>
                ))}
                {!customerQuery.searching && !customerQuery.isError && filteredCustomers.length === 0 && (
                  <div className="p-4 text-center text-bodytext text-sm">
                    {customerSearch.trim() ? 'No customers found' : 'Type a name, phone number or email'}
                  </div>
                )}
              </div>
            </div>
          )}
        </div>
      </div>

      {/* Cart Items */}
      <div className="cart-items flex-1 min-h-0 overflow-y-auto overscroll-contain p-3 space-y-2" style={{
        scrollbarWidth: 'thin'
      }}>
        {state.cart.length === 0 ? (
          <div className="text-center py-8">
            <div className="bg-lightgray p-5 rounded-3xl inline-block mb-3">
              <ShoppingCart className="h-10 w-10 text-bodytext" />
            </div>
            <p className="text-bodytext font-medium">Cart is empty</p>
            <p className="text-bodytext text-sm mt-1">Add products to get started</p>
            {!state.selectedCustomer && (
              <p className="text-bodytext text-xs mt-3 max-w-[16rem] mx-auto">
                Optional: add the customer to link purchases and record offers. The customer may decline.
              </p>
            )}
          </div>
        ) : (
          state.cart.map((item, index) => (
            <CartItemCard
              key={`${item.product.id}-${index}`}
              item={item}
              index={index}
              onUpdateQuantity={updateQuantity}
              onRemove={removeFromCart}
              onApplyDiscount={applyDiscount}
              isTouchMode={isTouchMode}
              currency={state.settings.currency}
            />
          ))
        )}
      </div>

      {/* Cart Summary */}
      {state.cart.length > 0 && (
        <div className="border-t border-border p-3 space-y-2.5 bg-lightgray flex-shrink-0">
          <div className="space-y-1 text-sm">
            <div className="cart-breakdown space-y-1">
            <div className="flex justify-between text-bodytext">
              <span>Subtotal:</span>
              <span className="font-medium">{state.settings.currency} {subtotal.toFixed(2)}</span>
            </div>
            {totalDiscount > 0 && (
              <div className="flex justify-between text-success">
                <span>Discount:</span>
                <span className="font-medium">-{state.settings.currency} {totalDiscount.toFixed(2)}</span>
              </div>
            )}
            <div className="flex justify-between text-bodytext">
              <span>Tax ({state.settings.taxRate}%):</span>
              <span className="font-medium">{state.settings.currency} {taxAmount.toFixed(2)}</span>
            </div>
            </div>
            <div className="flex justify-between text-lg font-bold text-link pt-1.5 mt-1 border-t border-border">
              <span>Total:</span>
              <span>{state.settings.currency} {total.toFixed(2)}</span>
            </div>
          </div>

          <div className="flex gap-2">
            <button
              onClick={onSaveDraft}
              disabled={state.cart.length === 0}
              className={`btn btn-secondary flex-shrink-0 ${
                isTouchMode ? 'btn-lg touch-friendly' : 'btn-md'
              }`}
            >
              <FileText className="h-4 w-4" />
              <span>Save Draft</span>
            </button>
            <button
              onClick={onCheckout}
              disabled={state.cart.length === 0}
              className={`btn btn-success flex-1 min-w-0 ${
                isTouchMode ? 'btn-lg touch-friendly' : 'btn-md'
              }`}
            >
              Checkout
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

interface CartItemCardProps {
  item: CartItem;
  index: number;
  onUpdateQuantity: (index: number, quantity: number) => void;
  onRemove: (index: number) => void;
  onApplyDiscount: (index: number, discount: number, type: 'percentage' | 'fixed') => void;
  isTouchMode: boolean;
  currency: string;
}

function CartItemCard({ item, index, onUpdateQuantity, onRemove, onApplyDiscount, isTouchMode, currency }: CartItemCardProps) {
  const [showDiscountInput, setShowDiscountInput] = useState(false);
  const [discountValue, setDiscountValue] = useState('');
  const [discountType, setDiscountType] = useState<'percentage' | 'fixed'>('percentage');

  const handleDiscountSubmit = () => {
    const value = parseFloat(discountValue);
    if (!isNaN(value) && value > 0) {
      onApplyDiscount(index, value, discountType);
      setShowDiscountInput(false);
      setDiscountValue('');
    }
  };

  return (
    <div className="rounded-xl border border-border bg-card px-3 py-2 space-y-1.5">
      {/* Row 1: what it is and what it costs */}
      <div className="flex items-baseline justify-between gap-2">
        <h4 className={`min-w-0 font-medium text-link truncate ${isTouchMode ? 'text-base' : 'text-sm'}`}>
          {item.product.name}
        </h4>
        <span className={`font-semibold whitespace-nowrap ${isTouchMode ? 'text-base' : 'text-sm'}`}>
          {currency} {item.subtotal.toFixed(2)}
        </span>
      </div>

      {/* Row 2: unit price, then the controls */}
      <div className="flex items-center justify-between gap-2">
        <div className="min-w-0 text-xs leading-tight text-bodytext">
          {/* On phones the unit price is dropped when it only repeats the line total. */}
          <p className={item.quantity === 1 && !item.discount ? 'max-sm:hidden' : undefined}>
            <><span className="max-sm:hidden">{currency} </span>{item.product.price.toFixed(2)} each</>
          </p>
          {item.discount > 0 && (
            <p className="text-success font-medium">
              Discount: {item.discountType === 'percentage' ? `${item.discount}%` : `${currency} ${item.discount.toFixed(2)}`}
            </p>
          )}
        </div>

        <div className="flex items-center gap-1 flex-shrink-0">
          <button
            onClick={() => onUpdateQuantity(index, item.quantity - 1)}
            aria-label={`Decrease ${item.product.name} quantity`}
            className={`btn btn-secondary p-0 ${
              isTouchMode ? 'w-12 h-12' : 'w-8 h-8 touch-friendly'
            } flex items-center justify-center`}
          >
            <Minus className="h-4 w-4" />
          </button>
          <span className={`font-medium min-w-7 text-center ${
            isTouchMode ? 'text-lg' : 'text-base'
          }`}>
            {item.quantity}
          </span>
          <button
            onClick={() => onUpdateQuantity(index, item.quantity + 1)}
            aria-label={`Increase ${item.product.name} quantity`}
            className={`btn btn-secondary p-0 ${
              isTouchMode ? 'w-12 h-12' : 'w-8 h-8 touch-friendly'
            } flex items-center justify-center`}
          >
            <Plus className="h-4 w-4" />
          </button>
          <button
            onClick={() => setShowDiscountInput(!showDiscountInput)}
            aria-label={`Discount ${item.product.name}`}
            aria-expanded={showDiscountInput}
            className={`text-primary hover:text-primary rounded-lg hover:bg-lightprimary transition-colors flex items-center justify-center ${isTouchMode ? 'w-12 h-12' : 'w-8 h-8 touch-friendly'}`}
          >
            <Percent className="h-4 w-4" />
          </button>
          <button
            onClick={() => onRemove(index)}
            aria-label={`Remove ${item.product.name}`}
            className={`text-error hover:text-error rounded-lg hover:bg-lighterror transition-colors flex items-center justify-center ${isTouchMode ? 'w-12 h-12' : 'w-8 h-8 touch-friendly'}`}
          >
            <Trash2 className="h-4 w-4" />
          </button>
        </div>
      </div>

      {showDiscountInput && (
        <div className="flex items-center space-x-2 pt-2 border-t border-border animate-slide-up">
          <select
            value={discountType}
            onChange={(e) => setDiscountType(e.target.value as 'percentage' | 'fixed')}
            className="select text-xs w-20"
          >
            <option value="percentage">%</option>
            <option value="fixed">{currency}</option>
          </select>
          <Input
            type="number"
            placeholder="Discount"
            value={discountValue}
            onChange={(e) => setDiscountValue(e.target.value)}
            className="input input-sm flex-1"
          />
          <button
            onClick={handleDiscountSubmit}
            className="btn btn-primary btn-sm"
          >
            Apply
          </button>
        </div>
      )}
    </div>
  );
}