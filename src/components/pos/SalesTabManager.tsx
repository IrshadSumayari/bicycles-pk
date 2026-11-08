import { Plus, X } from 'lucide-react';
import { useApp } from '../../context/SupabaseAppContext';
import { SalesTab } from '../../types';
import { salesTabsService } from '../../lib/services';
import { useAuth } from '../../context/AuthContext';

export function SalesTabManager() {
  const { state, dispatch } = useApp();
  const { user } = useAuth();

  const createNewTab = async () => {
    if (!user) return;
    
    try {
      // Save current tab's state before creating a new one
      if (state.activeSalesTab) {
        const currentTab = state.salesTabs.find(tab => tab.id === state.activeSalesTab);
        if (currentTab) {
          const updates = {
            cart: state.cart,
            selectedCustomer: state.selectedCustomer,
          };
          
          await salesTabsService.update(state.activeSalesTab, updates);
          dispatch({
            type: 'UPDATE_SALES_TAB',
            payload: {
              id: state.activeSalesTab,
              updates
            }
          });
        }
      }

      const newTabData: Omit<SalesTab, 'id' | 'createdAt'> = {
        name: `Sale ${state.salesTabs.length + 1}`,
        cart: [],
        selectedCustomer: null,
      };
      
      const newTab = await salesTabsService.create(user.id, newTabData);
      dispatch({ type: 'ADD_SALES_TAB', payload: newTab });
    } catch (error) {
      console.error('Error creating new tab:', error);
    }
  };

  const closeTab = async (tabId: string) => {
    if (state.salesTabs.length > 1) {
      try {
        await salesTabsService.delete(tabId);
        dispatch({ type: 'REMOVE_SALES_TAB', payload: tabId });
      } catch (error) {
        console.error('Error closing tab:', error);
      }
    }
  };

  const switchTab = async (tabId: string) => {
    // Save current cart to active tab
    if (state.activeSalesTab) {
      const currentTab = state.salesTabs.find(tab => tab.id === state.activeSalesTab);
      if (currentTab) {
        try {
          const updates = {
            cart: state.cart,
            selectedCustomer: state.selectedCustomer,
          };
          
          await salesTabsService.update(state.activeSalesTab, updates);
          dispatch({
            type: 'UPDATE_SALES_TAB',
            payload: {
              id: state.activeSalesTab,
              updates
            }
          });
        } catch (error) {
          console.error('Error saving current tab:', error);
        }
      }
    }
    
    dispatch({ type: 'SET_ACTIVE_SALES_TAB', payload: tabId });
  };

  const getItemCount = (tab: SalesTab) => {
    return tab.cart.reduce((sum, item) => sum + item.quantity, 0);
  };

  return (
    <div className="bg-card rounded-tw p-2 flex items-center gap-2 shrink-0">
      {/* Sale Buttons with Rotated Text */}
      <div className="flex-1 flex items-center overflow-x-auto gap-2 py-1">
        {state.salesTabs.map((tab, index) => {
          const isActive = state.activeSalesTab === tab.id;
          const itemCount = getItemCount(tab);
          const tabNumber = index + 1; // Correct sequential numbering
          
          return (
            <div
              key={tab.id}
              className={`relative group h-10 rounded-full flex items-center shrink-0 transition-all ${
                isActive
                  ? 'bg-primary text-white shadow-lg'
                  : 'bg-lightgray text-link hover:bg-border hover:shadow-md'
              }`}
            >
              <button
                onClick={() => switchTab(tab.id)}
                className={`h-full !min-h-0 rounded-full text-xs font-medium whitespace-nowrap ${
                  state.salesTabs.length > 1 ? 'pl-5 pr-2' : 'px-5'
                }`}
                aria-current={isActive ? 'true' : undefined}
              >
                Sale {tabNumber}
              </button>

              {/* Item Count Badge */}
              {itemCount > 0 && (
                <span className={`absolute -top-1 -right-1 w-4 h-4 rounded-full text-[10px] flex items-center justify-center pointer-events-none ${
                  isActive ? 'bg-card text-primary' : 'bg-primary text-white'
                }`}>
                  {itemCount}
                </span>
              )}

              {/* Close button, inside the tab */}
              {state.salesTabs.length > 1 && (
                <button
                  onClick={() => closeTab(tab.id)}
                  aria-label={`Close sale ${tabNumber}`}
                  title={`Close sale ${tabNumber}`}
                  className="mr-2 w-6 h-6 !min-h-0 rounded-full bg-[#dc2626] text-white flex items-center justify-center hover:bg-[#b91c1c] transition-colors"
                >
                  <X className="h-3 w-3" />
                </button>
              )}
            </div>
          );
        })}
      </div>

      {/* Add New Sale Button */}
      <div className="p-1 border-l border-border">
        <button
          onClick={createNewTab}
          className="btn btn-secondary btn-sm h-10 whitespace-nowrap"
          title="Add New Sale"
          aria-label="Add New Sale"
        >
          <Plus className="h-4 w-4" />
          <span className="hidden sm:inline">New sale</span>
        </button>
      </div>
    </div>
  );
}