import { MarketingPanel } from './MarketingPanel';
import {Input}from'@/components/ui/input';
import {DataTable}from'@/components/shared/DataTable';
import { StatCard } from '@/components/shared/StatCard';
import { useCustomerSearchText } from '../../lib/hooks/useCustomers';
import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { customersService } from '../../lib/services';
import { queryKeys } from '../../lib/queryClient';
import { ReportStatus } from '../reports/ReportStatus';
import { getErrorMessage } from '../../lib/errors';
import { Plus, Search, Edit, Trash2, User, Mail, Phone, CreditCard, Eye } from 'lucide-react';
import { Customer } from '../../types';
import { useApp } from '../../context/SupabaseAppContext';
import { CustomerModal } from './CustomerModal';
import { CustomerDetailModal } from './CustomerDetailModal';
import { swalConfig } from '../../lib/sweetAlert';

export function CustomerManager() {
  const { state } = useApp();
  const [section, setSection] = useState<'customers' | 'promotions'>('customers');
  const [searchTerm, setSearchTerm] = useState('');
  const debouncedSearch = useCustomerSearchText(searchTerm);
  const [owes, setOwes] = useState(false);
  const [page, setPage] = useState(0);
  // Recently updated first, so a customer just added or edited is on page 1
  const [sort, setSort] = useState<'name' | 'updated' | 'newest'>('updated');
  const query = useQuery({
    queryKey: queryKeys.customerList(state.currentUser!.id, { owes, q: debouncedSearch, sort }, page),
    queryFn: async () => {
      if (!owes) return customersService.list(page, 50, debouncedSearch, sort);
      const rows = await customersService.owing(debouncedSearch, page);
      return { rows, total: Number(rows[0]?.totalCount ?? 0) };
    },
  });
  const [showCustomerModal, setShowCustomerModal] = useState(false);
  const [editingCustomer, setEditingCustomer] = useState<Customer | null>(null);
  const [viewingCustomer, setViewingCustomer] = useState<Customer | null>(null);

  const filteredCustomers = query.data?.rows ?? [];

  const handleEditCustomer = (customer: Customer) => {
    setEditingCustomer(customer);
    setShowCustomerModal(true);
  };

  const handleViewCustomer = (customer: Customer) => {
    setViewingCustomer(customer);
  };

  const handleDeleteCustomer = async (customerId: string) => {
    const result = await swalConfig.deleteConfirm('customer');
    if (result.isConfirmed) {
      try {
        swalConfig.loading('Deleting customer...');
        const { customersService } = await import('../../lib/services');
        await customersService.delete(customerId);
        swalConfig.success('Customer deleted successfully!');
      } catch (error) {
        console.error('Error deleting customer:', error);
        swalConfig.error(getErrorMessage(error));
      }
    }
  };

  const handleAddCustomer = () => {
    setEditingCustomer(null);
    setShowCustomerModal(true);
  };

  const totalCustomers = query.data?.total ?? 0;
  const totalPurchases = filteredCustomers.reduce((sum: number, c: Customer) => sum + c.totalPurchases, 0);
  const averagePurchase = filteredCustomers.length > 0 ? totalPurchases / filteredCustomers.length : 0;
  const activeCustomers = filteredCustomers.filter((c: Customer) => c.lastPurchase &&
    new Date().getTime() - new Date(c.lastPurchase).getTime() < 30 * 24 * 60 * 60 * 1000
  ).length;

  return (
    <div className="p-4 md:p-6 space-y-6">
      <div className="flex gap-3"><button className={`btn btn-md ${section === 'customers' ? 'btn-primary' : 'btn-secondary'}`} onClick={() => setSection('customers')}>Customer directory</button><button className={`btn btn-md ${section === 'promotions' ? 'btn-primary' : 'btn-secondary'}`} onClick={() => setSection('promotions')}>Promotional email &amp; SMS</button></div>
      {section === 'promotions' ? <MarketingPanel /> : <>
      {/* Header Stats */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 md:gap-6">
        <StatCard label="Matching Customers" value={totalCustomers} icon={<User size={22} />} tone="primary" />
        <StatCard label="Purchases (this page)" value={`${state.settings.currency} ${totalPurchases.toFixed(2)}`} icon={<CreditCard size={22} />} tone="success" />
        <StatCard label="Average purchases (this page)" value={`${state.settings.currency} ${averagePurchase.toFixed(2)}`} icon={<Mail size={22} />} tone="secondary" />
        <StatCard label="Active (this page, 30 days)" value={activeCustomers} icon={<Phone size={22} />} tone="warning" />
      </div>

      {/* Controls */}
      <div className="bg-card p-4 md:p-6 rounded-2xl border border-border shadow-xs">
        <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center space-y-4 sm:space-y-0 gap-4">
          <div className="relative flex-1 max-w-md w-full">
            <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-bodytext h-5 w-5" />
            <Input
              type="text"
              placeholder="Search customers..."
              value={searchTerm}
              onChange={(e) => { setSearchTerm(e.target.value); setPage(0); }}
              className="w-full pl-10 pr-4 py-3 border border-border rounded-xl focus:ring-2 focus:ring-primary focus:border-transparent"
            />
          </div>

          {!owes && <select aria-label="Sort customers" className="select w-full sm:w-48" value={sort} onChange={e => { setSort(e.target.value as typeof sort); setPage(0); }}>
            <option value="updated">Recently updated</option>
            <option value="newest">Newest added</option>
            <option value="name">Name A-Z</option>
          </select>}
          <label className="flex items-center gap-2 text-sm"><input type="checkbox" className="h-4 w-4 rounded border-border accent-primary" checked={owes} onChange={e => { setOwes(e.target.checked); setPage(0); }} />Owes money</label>
          <button
            onClick={handleAddCustomer}
            className="flex items-center space-x-2 px-6 py-3 bg-linear-to-r from-primary to-primary text-white rounded-xl hover:from-primary hover:to-primary transition-all font-semibold shadow-lg hover:shadow-xl whitespace-nowrap"
          >
            <Plus className="h-5 w-5" />
            <span>Add Customer</span>
          </button>
        </div>
      </div>

      <ReportStatus loading={query.isPending} error={query.error} retry={() => void query.refetch()} />
      {/* Customer Table */}
      <div className="bg-card rounded-2xl border border-border shadow-xs overflow-hidden">
        <div className="overflow-x-auto">
          <DataTable className="min-w-full divide-y divide-border">
            <thead className="bg-lightgray">
              <tr>
                <th className="px-4 md:px-6 py-4 text-left text-xs font-semibold text-bodytext uppercase tracking-wider">
                  Customer
                </th>
                <th className="px-4 md:px-6 py-4 text-left text-xs font-semibold text-bodytext uppercase tracking-wider">
                  Contact
                </th>
                <th className="px-4 md:px-6 py-4 text-left text-xs font-semibold text-bodytext uppercase tracking-wider">
                  Balance
                </th>
                <th className="table-header-cell">Total Purchases</th>
                <th className="px-4 md:px-6 py-4 text-left text-xs font-semibold text-bodytext uppercase tracking-wider">
                  Price Tier
                </th>
                <th className="px-4 md:px-6 py-4 text-left text-xs font-semibold text-bodytext uppercase tracking-wider hidden sm:[display:table-cell]">
                  Last Purchase
                </th>
                <th className="px-4 md:px-6 py-4 text-right text-xs font-semibold text-bodytext uppercase tracking-wider">
                  Actions
                </th>
              </tr>
            </thead>
            <tbody className="bg-card divide-y divide-border">
              {filteredCustomers.map((customer: Customer) => (
                <tr key={customer.id} className="hover:bg-lightgray transition-colors">
                  <td className="px-4 md:px-6 py-4 whitespace-nowrap">
                    <div className="flex items-center">
                      <div className="h-10 w-10 bg-lightprimary text-primary rounded-full flex items-center justify-center flex-shrink-0 text-sm font-semibold" aria-hidden="true">
                        {customer.name.split(/\s+/).filter(Boolean).slice(0, 2).map(part => part[0]).join('').toUpperCase()}
                      </div>
                      <div className="ml-4 min-w-0">
                        <div className="text-sm font-semibold text-link truncate">{customer.name}</div>
                      </div>
                    </div>
                  </td>
                  <td className="px-4 md:px-6 py-4 whitespace-nowrap">
                    <div className="text-sm text-link truncate max-w-xs">{customer.email}</div>
                    <div className="text-sm text-bodytext">{customer.phone}</div>
                  </td>
                  <td className="px-4 md:px-6 py-4 whitespace-nowrap text-sm font-semibold text-link">
                    {state.settings.currency} {customer.creditUsed.toFixed(2)}
                    {owes && 'oldestUnpaidDate' in customer && <p className="text-xs text-bodytext">Oldest debit: {String(customer.oldestUnpaidDate ?? '—')}</p>}
                    {owes && 'lastPaymentDate' in customer && <p className="text-xs text-bodytext">Last payment: {String(customer.lastPaymentDate ?? '—')}</p>}
                  </td>
                  <td className="table-cell whitespace-nowrap">
                    {state.settings.currency} {customer.totalPurchases.toFixed(2)}
                  </td>
                  <td className="px-4 md:px-6 py-4 whitespace-nowrap">
                    <span className="inline-flex px-3 py-1 text-xs font-semibold rounded-full bg-lightprimary text-primary">
                      {customer.priceTier}
                    </span>
                  </td>
                  <td className="px-4 md:px-6 py-4 whitespace-nowrap text-sm text-link hidden sm:[display:table-cell]">
                    {customer.lastPurchase
                      ? new Date(customer.lastPurchase).toLocaleDateString()
                      : 'Never'
                    }
                  </td>
                  <td className="px-4 md:px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                    <div className="flex items-center justify-end space-x-2">
                      <button
                        onClick={() => handleViewCustomer(customer)}
                        className="text-success hover:text-success p-2 rounded-lg hover:bg-lightsuccess transition-colors"
                        title="View Details"
                      >
                        <Eye className="h-4 w-4" />
                      </button>
                      <button
                        onClick={() => handleEditCustomer(customer)}
                        className="text-primary hover:text-primary p-2 rounded-lg hover:bg-lightprimary transition-colors"
                        title="Edit Customer"
                      >
                        <Edit className="h-4 w-4" />
                      </button>
                      <button
                        onClick={() => handleDeleteCustomer(customer.id)}
                        className="text-error hover:text-error p-2 rounded-lg hover:bg-lighterror transition-colors"
                        title="Delete Customer"
                      >
                        <Trash2 className="h-4 w-4" />
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </DataTable>
        </div>
      </div>

      <div className="flex flex-wrap items-center gap-3 text-sm">
        <span>Showing {filteredCustomers.length ? page * 50 + 1 : 0}–{filteredCustomers.length ? page * 50 + filteredCustomers.length : 0} of {totalCustomers}</span>
        {owes && <span>Oldest debit shows the oldest positive account entry.</span>}
        <button type="button" className="btn btn-secondary btn-sm" disabled={!page || query.isFetching} onClick={() => setPage(page - 1)}>Previous</button>
        <button type="button" className="btn btn-secondary btn-sm" disabled={query.isFetching || (page + 1) * 50 >= totalCustomers} onClick={() => setPage(page + 1)}>Next</button>
      </div>
      </>}
      <CustomerModal
        isOpen={showCustomerModal}
        onClose={() => setShowCustomerModal(false)}
        customer={editingCustomer}
      />

      {viewingCustomer && (
        <CustomerDetailModal
          customer={viewingCustomer}
          onClose={() => setViewingCustomer(null)}
        />
      )}
    </div>
  );
}
