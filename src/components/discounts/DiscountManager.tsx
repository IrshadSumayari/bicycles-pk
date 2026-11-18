import {Input}from'@/components/ui/input';
import {DataTable}from'@/components/shared/DataTable';
import { StatCard } from '@/components/shared/StatCard';
import { useDiscounts } from '../../lib/hooks/useDiscounts';
import { ReportStatus } from '../reports/ReportStatus';
import { getErrorMessage } from '../../lib/errors';
import { useState } from 'react';
import { Plus, Search, Edit, Trash2, Percent, Gift } from 'lucide-react';
import { Discount } from '../../types';
import { useApp } from '../../context/SupabaseAppContext';
import { DiscountModal } from './DiscountModal';
import { DiscountCodesPanel } from './DiscountCodesPanel';
import { format } from 'date-fns';
import { swalConfig } from '../../lib/sweetAlert';

export function DiscountManager() {
  const { state } = useApp();
  const query = useDiscounts();
  const discounts = query.data ?? [];
  const [searchTerm, setSearchTerm] = useState('');
  const [showDiscountModal, setShowDiscountModal] = useState(false);
  const [editingDiscount, setEditingDiscount] = useState<Discount | null>(null);

  const filteredDiscounts = discounts.filter(discount =>
    discount.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
    discount.description.toLowerCase().includes(searchTerm.toLowerCase())
  );

  const handleEditDiscount = (discount: Discount) => {
    setEditingDiscount(discount);
    setShowDiscountModal(true);
  };

  const handleDeleteDiscount = async (discountId: string) => {
    const result = await swalConfig.deleteConfirm('discount');
    if (result.isConfirmed) {
      try {
        swalConfig.loading('Deleting discount...');
        const { discountsService } = await import('../../lib/services');
        await discountsService.delete(discountId);
        swalConfig.success('Discount deleted successfully!');
      } catch (error) {
        console.error('Error deleting discount:', error);
        swalConfig.error(getErrorMessage(error));
      }
    }
  };

  const handleAddDiscount = () => {
    setEditingDiscount(null);
    setShowDiscountModal(true);
  };

  const toggleDiscountStatus = async (discount: Discount) => {
    try {
      swalConfig.loading(`${discount.active ? 'Deactivating' : 'Activating'} discount...`);
      const updatedDiscount = { ...discount, active: !discount.active };
      const { discountsService } = await import('../../lib/services');
      await discountsService.update(discount.id, updatedDiscount);
      swalConfig.success(`Discount ${discount.active ? 'deactivated' : 'activated'} successfully!`);
    } catch (error) {
      console.error('Error updating discount:', error);
      swalConfig.error(getErrorMessage(error));
    }
  };

  const getDiscountTypeIcon = (type: string) => {
    switch (type) {
      case 'percentage':
      case 'fixed':
        return <Percent className="h-4 w-4" />;
      case 'free_gift':
        return <Gift className="h-4 w-4" />;
      default:
        return <Percent className="h-4 w-4" />;
    }
  };

  const getDiscountTypeColor = (type: string) => {
    switch (type) {
      case 'percentage':
        return 'bg-lightprimary text-primary';
      case 'fixed':
        return 'bg-lightsuccess text-success';
      case 'free_gift':
        return 'bg-lightprimary text-primary';
      default:
        return 'bg-lightgray text-link';
    }
  };

  return (
    <div className="p-4 lg:p-6 space-y-6 bg-lightgray min-h-full">
      <ReportStatus loading={query.isPending} error={query.error} retry={() => void query.refetch()} />
      {/* Header */}
      <div className="flex flex-col lg:flex-row justify-between items-start lg:items-center space-y-4 lg:space-y-0">
        <div>
          <p className="text-bodytext mt-1">Manage automatic discounts and promotional offers</p>
        </div>
        
        <button
          onClick={handleAddDiscount}
          className="btn btn-primary btn-lg"
        >
          <Plus className="h-5 w-5" />
          <span>Add Discount</span>
        </button>
      </div>

      {/* Stats Cards */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 lg:gap-6">
        <StatCard label="Total Discounts" value={discounts.length} icon={<Percent size={22} />} tone="primary" progress={discounts.length ? 100 : 0} />
        <StatCard label="Active Discounts" value={discounts.filter(d => d.active).length} icon={<Gift size={22} />} tone="success" progress={discounts.length ? (discounts.filter(d => d.active).length / discounts.length) * 100 : 0} />
        <StatCard label="Percentage Discounts" value={discounts.filter(d => d.type === 'percentage').length} icon={<Percent size={22} />} tone="secondary" progress={discounts.length ? (discounts.filter(d => d.type === 'percentage').length / discounts.length) * 100 : 0} />
        <StatCard label="Free Gift Offers" value={discounts.filter(d => d.type === 'free_gift').length} icon={<Gift size={22} />} tone="warning" progress={discounts.length ? (discounts.filter(d => d.type === 'free_gift').length / discounts.length) * 100 : 0} />
      </div>

      {/* Controls */}
      <div className="card p-4 lg:p-6">
        <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center space-y-4 sm:space-y-0 gap-4">
          <div className="relative flex-1 max-w-md">
            <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-bodytext h-5 w-5" />
            <Input
              type="text"
              placeholder="Search discounts..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              className="input pl-10"
            />
          </div>
        </div>
      </div>

      {/* Discounts Table */}
      <div className="card overflow-hidden">
        <div className="overflow-x-auto">
          <DataTable className="table">
            <thead className="table-header">
              <tr>
                <th className="table-header-cell">Discount</th>
                <th className="table-header-cell">Type</th>
                <th className="table-header-cell">Value</th>
                <th className="table-header-cell">Conditions</th>
                <th className="table-header-cell">Valid Period</th>
                <th className="table-header-cell">Status</th>
                <th className="table-header-cell text-right">Actions</th>
              </tr>
            </thead>
            <tbody className="bg-card divide-y divide-border">
              {filteredDiscounts.map((discount) => (
                <tr key={discount.id} className="table-row">
                  <td className="table-cell">
                    <div>
                      <div className="text-sm font-semibold text-link">{discount.name}</div>
                      <div className="text-xs text-bodytext">{discount.description}</div>
                    </div>
                  </td>
                  <td className="table-cell">
                    <span className={`badge ${getDiscountTypeColor(discount.type)} flex items-center space-x-1`}>
                      {getDiscountTypeIcon(discount.type)}
                      <span className="capitalize">{discount.type.replace('_', ' ')}</span>
                    </span>
                  </td>
                  <td className="table-cell font-semibold">
                    {discount.type === 'percentage' && `${discount.value}%`}
                    {discount.type === 'fixed' && `${state.settings.currency} ${discount.value}`}
                    {discount.type === 'free_gift' && 'Free Gift'}
                  </td>
                  <td className="table-cell">
                    <div className="text-xs text-bodytext">
                      {discount.conditions.length} condition(s)
                    </div>
                  </td>
                  <td className="table-cell">
                    <div className="text-xs">
                      <div>{format(new Date(discount.validFrom), 'MMM dd, yyyy')}</div>
                      <div className="text-bodytext">to {format(new Date(discount.validTo), 'MMM dd, yyyy')}</div>
                    </div>
                  </td>
                  <td className="table-cell">
                    <button
                      onClick={() => toggleDiscountStatus(discount)}
                      className={`badge ${
                        discount.active ? 'badge-success' : 'badge-danger'
                      } cursor-pointer hover:opacity-80`}
                    >
                      {discount.active ? 'Active' : 'Inactive'}
                    </button>
                  </td>
                  <td className="table-cell text-right">
                    <div className="flex items-center justify-end space-x-2">
                      <button
                        onClick={() => handleEditDiscount(discount)}
                        className="text-primary hover:text-primary p-2 rounded-lg hover:bg-lightprimary transition-colors"
                      >
                        <Edit className="h-4 w-4" />
                      </button>
                      <button
                        onClick={() => handleDeleteDiscount(discount.id)}
                        className="text-error hover:text-error p-2 rounded-lg hover:bg-lighterror transition-colors"
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

      <DiscountCodesPanel />

      <DiscountModal
        isOpen={showDiscountModal}
        onClose={() => setShowDiscountModal(false)}
        discount={editingDiscount}
      />
    </div>
  );
}