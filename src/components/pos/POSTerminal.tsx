import { useState } from 'react';
import { ProductGrid } from './ProductGrid';
import { Cart } from './Cart';
import { CheckoutModal } from './CheckoutModal';
import { CashShiftBar } from './CashShiftBar';
import { SalesTabManager } from './SalesTabManager';
import { Product, Sale } from '../../types';
import { useApp } from '../../context/SupabaseAppContext';
import { salesService } from '../../lib/services';
import { swalConfig } from '../../lib/sweetAlert';

export function POSTerminal() {
  const { state, dispatch } = useApp();
  const [showCheckout, setShowCheckout] = useState(false);
  const [, setLastSale] = useState<Sale | null>(null);

  const addToCart = (product: Product) => {
    // Only check stock if inventory tracking is enabled
    if (product.trackInventory && product.stock <= 0) return;

    const existingItemIndex = state.cart.findIndex(item => item.product.id === product.id);
    
    if (existingItemIndex >= 0) {
      const existingItem = state.cart[existingItemIndex];
      const newQuantity = existingItem.quantity + 1;
      
      // Only check stock limits if inventory tracking is enabled
      if (!product.trackInventory || newQuantity <= product.stock) {
        const updatedItem = {
          ...existingItem,
          quantity: newQuantity,
          subtotal: product.price * newQuantity - (existingItem.discount || 0)
        };
        dispatch({ type: 'UPDATE_CART_ITEM', payload: { index: existingItemIndex, item: updatedItem } });
      }
    } else {
      const newItem = {
        product,
        quantity: 1,
        discount: 0,
        discountType: 'percentage' as const,
        subtotal: product.price
      };
      dispatch({ type: 'ADD_TO_CART', payload: newItem });
    }

    // Update current sales tab
    if (state.activeSalesTab) {
      dispatch({
        type: 'UPDATE_SALES_TAB',
        payload: {
          id: state.activeSalesTab,
          updates: { cart: state.cart }
        }
      });
    }
  };

  const handleCheckout = () => {
    setShowCheckout(true);
  };

  const handleCheckoutComplete = (sale: Sale) => {
    setLastSale(sale);
    setShowCheckout(false);
    
    // Clear current tab after successful checkout
    if (state.activeSalesTab) {
      dispatch({
        type: 'UPDATE_SALES_TAB',
        payload: {
          id: state.activeSalesTab,
          updates: { cart: [], selectedCustomer: null }
        }
      });
    }
  };

  const saveDraft = async () => {
    if (state.cart.length === 0) return;

    try {
      // Drafts don't touch stock or credit; the server assigns a DRAFT- number
      await salesService.post({
        requestId: crypto.randomUUID(),
        status: 'draft',
        cart: state.cart,
        customerId: state.selectedCustomer?.id,
        payments: [],
        notes: 'DRAFT_SALE - payment pending',
      });
      dispatch({ type: 'CLEAR_CART' });
      
      // Clear current tab
      if (state.activeSalesTab) {
        dispatch({
          type: 'UPDATE_SALES_TAB',
          payload: {
            id: state.activeSalesTab,
            updates: { cart: [], selectedCustomer: null }
          }
        });
      }

      swalConfig.success('Draft sale saved successfully!');
    } catch (error) {
      console.error('Error saving draft:', error);
      swalConfig.error('Failed to save draft. Please try again.');
    }
  };

  return (
    <div className="flex flex-col h-full gap-3 bg-lightgray">
      <CashShiftBar />
      <div className="till-workspace flex flex-col flex-1 min-h-0 gap-3">
      <SalesTabManager />
      <div className="till-products-cart flex flex-1 overflow-hidden gap-4">
        <ProductGrid onAddToCart={addToCart} />
        <Cart onCheckout={handleCheckout} onSaveDraft={saveDraft} />
        
        <CheckoutModal
          isOpen={showCheckout}
          onClose={() => setShowCheckout(false)}
          onComplete={handleCheckoutComplete}
        />
      </div>
      </div>
    </div>
  );
}