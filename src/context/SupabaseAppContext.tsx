import React, { createContext, useContext, useReducer, useEffect, useState } from 'react';
import {
  Customer, User, CartItem, AppSettings, SalesTab
} from '../types';
import { useAuth } from './AuthContext';
import {
  settingsService,
  salesTabsService
} from '../lib/services';

import { getErrorMessage } from '../lib/errors';
import { queryClient } from '../lib/queryClient';
interface AppState {
  cart: CartItem[];
  currentUser: User | null;
  settings: AppSettings;
  selectedCustomer: Customer | null;
  salesTabs: SalesTab[];
  activeSalesTab: string;
  loading: boolean;
  error: string | null;
}

type AppAction =
  | { type: 'SET_LOADING'; payload: boolean }
  | { type: 'SET_ERROR'; payload: string | null }
  | { type: 'SET_CART'; payload: CartItem[] }
  | { type: 'ADD_TO_CART'; payload: CartItem }
  | { type: 'UPDATE_CART_ITEM'; payload: { index: number; item: CartItem } }
  | { type: 'REMOVE_FROM_CART'; payload: number }
  | { type: 'CLEAR_CART' }
  | { type: 'SET_CURRENT_USER'; payload: User | null }
  | { type: 'SET_SELECTED_CUSTOMER'; payload: Customer | null }
  | { type: 'SET_SETTINGS'; payload: Partial<AppSettings> }
  | { type: 'INCREMENT_INVOICE_COUNTER'; payload: number }
  | { type: 'ADD_SALES_TAB'; payload: SalesTab }
  | { type: 'UPDATE_SALES_TAB'; payload: { id: string; updates: Partial<SalesTab> } }
  | { type: 'REMOVE_SALES_TAB'; payload: string }
  | { type: 'SET_ACTIVE_SALES_TAB'; payload: string }
  | { type: 'SET_SALES_TABS'; payload: SalesTab[] };

const initialState: AppState = {
  cart: [],
  currentUser: null,
  selectedCustomer: null,
  settings: {
    storeName: 'LadyVogue POS',
    storeAddress: '',
    storePhone: '',
    storeEmail: '',
    taxRate: 0,
    currency: 'PKR',
    interfaceMode: 'touch',
    autoBackup: true,
    receiptPrinter: true,
    theme: 'light',
    invoicePrefix: 'INV',
    invoiceCounter: 1000,
  },
  salesTabs: [],
  activeSalesTab: '',
  loading: false,
  error: null,
};

function appReducer(state: AppState, action: AppAction): AppState {
  switch (action.type) {
    case 'SET_LOADING':
      return { ...state, loading: action.payload };
    case 'SET_ERROR':
      return { ...state, error: action.payload };
    case 'SET_CART':
      return { ...state, cart: action.payload };
    case 'ADD_TO_CART':
      return { ...state, cart: [...state.cart, action.payload] };
    case 'UPDATE_CART_ITEM':
      return {
        ...state,
        cart: state.cart.map((item, index) =>
          index === action.payload.index ? action.payload.item : item
        ),
      };
    case 'REMOVE_FROM_CART':
      return {
        ...state,
        cart: state.cart.filter((_, index) => index !== action.payload),
      };
    case 'CLEAR_CART':
      return { ...state, cart: [], selectedCustomer: null };
    case 'SET_CURRENT_USER':
      return { ...state, currentUser: action.payload };
    case 'SET_SELECTED_CUSTOMER':
      return { ...state, selectedCustomer: action.payload };
    case 'SET_SETTINGS':
      return { ...state, settings: { ...state.settings, ...action.payload } };
    case 'INCREMENT_INVOICE_COUNTER':
      return {
        ...state,
        settings: {
          ...state.settings,
          invoiceCounter: action.payload
        }
      };
    case 'ADD_SALES_TAB':
      return {
        ...state,
        salesTabs: [...state.salesTabs, action.payload],
        activeSalesTab: action.payload.id,
        cart: action.payload.cart || [],
        selectedCustomer: action.payload.selectedCustomer || null,
      };
    case 'UPDATE_SALES_TAB':
      return {
        ...state,
        salesTabs: state.salesTabs.map(tab =>
          tab.id === action.payload.id ? { ...tab, ...action.payload.updates } : tab
        ),
      };
    case 'REMOVE_SALES_TAB': {
      const remainingTabs = state.salesTabs.filter(tab => tab.id !== action.payload);
      return {
        ...state,
        salesTabs: remainingTabs,
        activeSalesTab: remainingTabs.length > 0 ? remainingTabs[0].id : '',
      };
    }
    case 'SET_ACTIVE_SALES_TAB': {
      const activeTab = state.salesTabs.find(tab => tab.id === action.payload);
      return {
        ...state,
        activeSalesTab: action.payload,
        cart: activeTab?.cart || [],
        selectedCustomer: activeTab?.selectedCustomer || null,
      };
    }
    case 'SET_SALES_TABS':
      return { ...state, salesTabs: action.payload };
    default:
      return state;
  }
}

const AppContext = createContext<{
  state: AppState;
  dispatch: React.Dispatch<AppAction>;
} | null>(null);

export function AppProvider({ children }: { children: React.ReactNode }) {
  const [state, dispatch] = useReducer(appReducer, initialState);
  const { user, profile } = useAuth();
  const [initialized, setInitialized] = useState(false);

  // Load data from Supabase when user is authenticated
  useEffect(() => {
    if (user && profile?.active && !initialized) {
      loadData();
      setInitialized(true);
    } else if (!user) {
      // Reset state when user logs out (shared tills: never show the previous user's data)
      queryClient.clear();
      dispatch({ type: 'SET_SALES_TABS', payload: [] });
      dispatch({ type: 'CLEAR_CART' });
      dispatch({ type: 'SET_CURRENT_USER', payload: null });
      setInitialized(false);
    }
  }, [user, profile, initialized]);

  // Set current user from auth profile
  useEffect(() => {
    if (profile) {
      dispatch({ type: 'SET_CURRENT_USER', payload: profile });
    }
  }, [profile]);

  async function loadData() {
    dispatch({ type: 'SET_LOADING', payload: true });
    try {
      // Load all data in parallel
      const [
        settings,
        salesTabs
      ] = await Promise.all([
        settingsService.get(),
        user ? salesTabsService.getByUserId(user.id) : Promise.resolve([])
      ]);

      dispatch({ type: 'SET_SETTINGS', payload: settings });
      dispatch({ type: 'SET_SALES_TABS', payload: salesTabs });

      // Create initial sales tab if none exist
      if (salesTabs.length === 0 && user) {
        const initialTab: Omit<SalesTab, 'id' | 'createdAt'> = {
          name: 'Sale 1',
          cart: [],
          selectedCustomer: null,
        };
        const newTab = await salesTabsService.create(user.id, initialTab);
        dispatch({ type: 'ADD_SALES_TAB', payload: newTab });
      } else if (salesTabs.length > 0) {
        dispatch({ type: 'SET_ACTIVE_SALES_TAB', payload: salesTabs[0].id });
      }

      dispatch({ type: 'SET_ERROR', payload: null });
    } catch (error) {
      console.error('Error loading data:', error);
      dispatch({ type: 'SET_ERROR', payload: getErrorMessage(error) });
    } finally {
      dispatch({ type: 'SET_LOADING', payload: false });
    }
  }

  return (
    <AppContext.Provider value={{ state, dispatch }}>
      {children}
    </AppContext.Provider>
  );
}

export function useApp() {
  const context = useContext(AppContext);
  if (!context) {
    throw new Error('useApp must be used within an AppProvider');
  }
  return context;
}

// Invoice numbers are assigned by the database (post_sale) so two tills can
// never issue the same number. This only previews the next one.
export function getNextInvoiceNumber(settings: AppSettings): string {
  const nextCounter = settings.invoiceCounter + 1;
  return `${settings.invoicePrefix}-${nextCounter.toString().padStart(6, '0')}`;
}

// Utility functions for invoice counter management
export function resetInvoiceCounter(dispatch: React.Dispatch<AppAction>, newCounter: number = 0) {
  dispatch({ type: 'INCREMENT_INVOICE_COUNTER', payload: newCounter });
}

export function setInvoicePrefix(dispatch: React.Dispatch<AppAction>, prefix: string) {
  dispatch({ type: 'SET_SETTINGS', payload: { invoicePrefix: prefix } });
}
