import { sectionById } from '../../../shared/bicycles';
import { allDepartmentCategory, inventoryCategoryFilter, inventoryCategoryOptions, newStyleCategory, type Department } from '../../lib/inventoryCategory';
import { inventoryMetrics } from '../../lib/inventoryMetrics';
import {MoreHorizontal}from'lucide-react';
import {DropdownMenu,DropdownMenuTrigger,DropdownMenuContent,DropdownMenuItem}from'@/components/ui/dropdown-menu';
import {Input}from'@/components/ui/input';
import {DataTable}from'@/components/shared/DataTable';
import { StatCard } from '@/components/shared/StatCard';
import { useQuery } from '@tanstack/react-query';
import { webCatalogService, type ProductSort } from '../../lib/services';
import { queryKeys } from '../../lib/queryClient';
import { CollectionsManager } from './CollectionsManager';
import { useProductSearch, useProductCategories } from '../../lib/hooks/useProducts';
import { useCoverImages } from '../../lib/hooks/useCoverImages';
import { ReportStatus } from '../reports/ReportStatus';
import { useState } from 'react';
import { Plus, Search, Edit, Trash2, Package, AlertTriangle, TrendingUp, TrendingDown, Boxes, Tag } from 'lucide-react';
import { Product, productLabel } from '../../types';
import { useApp } from '../../context/SupabaseAppContext';
import { StyleModal } from './StyleModal';
import { StockAdjustModal } from './StockAdjustModal';
import { GoodsReceiptPanel } from './GoodsReceiptPanel';
import { StockCountPanel } from './StockCountPanel';
import { LabelPrintModal } from './LabelPrintModal';
import { ProductImportPanel } from './ProductImportPanel';
import { swalConfig } from '../../lib/sweetAlert';

type InventoryOrder = ProductSort | 'name-desc' | 'stock-asc' | 'stock-desc' | 'price-asc' | 'price-desc';

export function InventoryManager({ department }: { department?: Department } = {}) {
  const { state } = useApp();
  const [searchTerm, setSearchTerm] = useState('');
  const [selectedCategory, setSelectedCategory] = useState(allDepartmentCategory(department));
  const [showStyleModal, setShowStyleModal] = useState(false);
  const [editingStyleId, setEditingStyleId] = useState<string | null>(null);
  const [adjustingProduct, setAdjustingProduct] = useState<Product | null>(null);
  const [labelItems, setLabelItems] = useState<Product[] | null>(null);
  const [tab, setTab] = useState<'stock' | 'receive' | 'count' | 'import' | 'collections'>('stock');
  // Recently updated first by default, so a style just added or edited is on page 1
  const [order, setOrder] = useState<InventoryOrder>('updated');
  const serverSort: ProductSort = order === 'updated' || order === 'newest' ? order : 'name';
  const [sortBy, sortOrder] = (order.includes('-') ? order.split('-') : ['', 'asc']) as ['' | 'name' | 'stock' | 'price', 'asc' | 'desc'];

  const canPublish = ['admin', 'manager'].includes(state.currentUser?.role ?? '');
  const [publication, setPublication] = useState<'all' | 'published' | 'unpublished'>('all');
  const [page, setPage] = useState(0);
  const categoryFilter = inventoryCategoryFilter(selectedCategory);
  const stockQuery = useProductSearch({ q: searchTerm, ...categoryFilter, limit: 50, offset: page * 50, withCosts: true, sort: serverSort }, tab === 'stock' && publication === 'all');
  const webParams = { q: searchTerm, ...categoryFilter, published: publication === 'published', page, sort: serverSort };
  const webQuery = useQuery({ queryKey: queryKeys.webInventory(webParams), queryFn: () => webCatalogService.inventory(webParams), enabled: tab === 'stock' && publication !== 'all' && canPublish });
  const query = publication === 'all' ? stockQuery : { ...webQuery, searching: webQuery.isFetching };
  const categoryQuery = useProductCategories();
  const categories = inventoryCategoryOptions(department, categoryQuery.data ?? []);
  const products = query.data?.rows ?? [];
  const styleIds = [...new Set(products.map(product => product.styleId))].sort();
  const flags = useQuery({ queryKey: queryKeys.webFlags(styleIds), queryFn: () => webCatalogService.flags(styleIds), enabled: canPublish && styleIds.length > 0 });
  const publishedIds = new Set(flags.data?.filter(style => style.published).map(style => style.id));
  const thumbnail = useCoverImages(products);

  const filteredProducts = !sortBy ? products : [...products].sort((a, b) => {
      let aValue: string | number;
      let bValue: string | number;

      switch (sortBy) {
        case 'name':
          aValue = a.name.toLowerCase();
          bValue = b.name.toLowerCase();
          break;
        case 'stock':
          aValue = a.stock;
          bValue = b.stock;
          break;
        case 'price':
          aValue = a.price;
          bValue = b.price;
          break;
        default:
          aValue = a.name.toLowerCase();
          bValue = b.name.toLowerCase();
      }

      if (sortOrder === 'asc') {
        return aValue < bValue ? -1 : aValue > bValue ? 1 : 0;
      } else {
        return aValue > bValue ? -1 : aValue < bValue ? 1 : 0;
      }
    });

  const metrics = inventoryMetrics(products, query.data?.total ?? 0);

  const handleEditProduct = (product: Product) => {
    setEditingStyleId(product.styleId);
    setShowStyleModal(true);
  };

  const handleDeleteProduct = async (productId: string) => {
    const result = await swalConfig.deleteConfirm('product');
    if (result.isConfirmed) {
      try {
        swalConfig.loading('Removing product...');
        const { productsService } = await import('../../lib/services');
        // Hidden, not deleted: its sales and stock history stay intact
        await productsService.delete(productId);
        setPage(0);
        swalConfig.success('Product removed from sale');
      } catch (error) {
        console.error('Error deleting product:', error);
        swalConfig.error('Failed to delete product. Please try again.');
      }
    }
  };

  const handleAddProduct = () => {
    setEditingStyleId(null);
    setShowStyleModal(true);
  };

  return (
    <div className="p-4 lg:p-6 space-y-6 bg-lightgray min-h-full min-w-0 max-w-full">
      {/* Header */}
      <div className="flex flex-col lg:flex-row justify-between items-start lg:items-center space-y-4 lg:space-y-0">
        <div>
          <p className="text-bodytext mt-1">{department ? `${sectionById(department).description} Choose a category to manage its sizes and colours.` : 'Manage your products and stock levels'}</p>
        </div>
        
        {tab === 'stock' && <div className="flex flex-wrap gap-2">
        <button onClick={() => setLabelItems(filteredProducts.filter(p => p.kind !== 'service'))} className="btn btn-secondary btn-lg">
          <Tag className="h-5 w-5" />
          <span>Print labels</span>
        </button>
        <button
          onClick={handleAddProduct}
          className="btn btn-primary btn-lg"
        >
          <Plus className="h-5 w-5" />
          <span>Add style</span>
        </button>
        </div>}
      </div>

      <div className="flex flex-wrap gap-2 border-b border-border">
        {([['stock', 'Stock'], ['receive', 'Receive goods'], ['count', 'Stock count'], ['import', 'Import']] as const).filter(([id]) => !department || id === 'stock' || id === 'import').map(([id, label]) => (
          <button key={id} type="button" onClick={() => setTab(id)}
                  className={`px-4 py-2 -mb-px border-b-2 font-medium ${tab === id ? 'border-primary text-primary' : 'border-transparent text-bodytext hover:text-link'}`}>
            {label}
          </button>
        ))}
        {canPublish && !department && <button type="button" onClick={() => setTab('collections')}
                  className={`px-4 py-2 -mb-px border-b-2 font-medium ${tab === 'collections' ? 'border-primary text-primary' : 'border-transparent text-bodytext hover:text-link'}`}>Collections</button>}
      </div>

      {tab === 'collections' && canPublish ? <CollectionsManager /> : tab === 'receive' ? <GoodsReceiptPanel /> : tab === 'count' ? <StockCountPanel /> : tab === 'import' ? <ProductImportPanel /> : (
      <>
      <ReportStatus loading={query.isPending} error={query.error ?? categoryQuery.error ?? flags.error} retry={() => { void query.refetch(); void categoryQuery.refetch(); if (styleIds.length) void flags.refetch(); }} />
      {/* Stats Cards */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 lg:gap-6">
        <StatCard label="Matching Products" value={query.data?.total ?? 0} icon={<Package size={22} />} tone="primary" progress={metrics.loadedProgress} progressLabel="Matching products shown on this page" />
        <StatCard label="Low Stock Items (this page)" value={metrics.lowCount} icon={<AlertTriangle size={22} />} tone="warning" progress={metrics.lowProgress} progressLabel="Share of tracked items with low stock on this page" />
        <StatCard label="Inventory Value (this page)" value={`${state.settings.currency} ${metrics.value.toFixed(2)}`} icon={<TrendingUp size={22} />} tone="success" progress={metrics.valuedProgress} progressLabel="Share of tracked items with stock and recorded cost on this page" />
        <StatCard label="Out of Stock (this page)" value={metrics.emptyCount} icon={<TrendingDown size={22} />} tone="error" progress={metrics.emptyProgress} progressLabel="Share of tracked items out of stock on this page" />
      </div>

      {/* Filters and Controls */}
      <div className="card p-4 lg:p-6">
        <div className="min-w-0">
          <div className="grid grid-cols-1 sm:grid-cols-2 2xl:grid-cols-4 gap-4 min-w-0 w-full">
            <div className="relative min-w-0">
              <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-bodytext h-5 w-5" />
              <Input
                type="text"
                placeholder={publication === 'all' ? "Search products..." : "Search by style name..."}
                value={searchTerm}
                onChange={(e) => { setSearchTerm(e.target.value); setPage(0); }}
                className="input pl-10"
              />
            </div>

            {canPublish && <select aria-label="Website publication" className="select w-full min-w-0 max-w-full" value={publication} onChange={event => { setPublication(event.target.value as typeof publication); setPage(0); }}><option value="all">All</option><option value="published">Published</option><option value="unpublished">Not published</option></select>}
            <select
              aria-label="Category"
              value={selectedCategory}
              onChange={(e) => { setSelectedCategory(e.target.value); setPage(0); }}
              className="select w-full min-w-0 max-w-full"
            >
              {categories.map(category => (
                <option key={category} value={category}>{category}</option>
              ))}
            </select>

            <select
              aria-label="Sort products"
              value={order}
              onChange={(e) => { setOrder(e.target.value as InventoryOrder); setPage(0); }}
              className="select w-full min-w-0 max-w-full"
            >
              <optgroup label="All products">
                <option value="updated">Recently updated</option>
                <option value="newest">Newest added</option>
                <option value="name">Name A-Z</option>
              </optgroup>
              <optgroup label="This page only">
              <option value="name-desc">Name Z-A (this page)</option>
              <option value="name-desc">Name Z-A (this page)</option>
              <option value="stock-asc">Stock Low-High (this page)</option>
              <option value="stock-desc">Stock High-Low (this page)</option>
              <option value="price-asc">Price Low-High (this page)</option>
              <option value="price-desc">Price High-Low (this page)</option>
              </optgroup>
            </select>
          </div>
        </div>
      </div>

      {/* Products Table */}
      <div className="card overflow-hidden">
        <div className="overflow-x-auto">
          <DataTable className="table">
            <thead className="table-header">
              <tr>
                <th className="table-header-cell">Product</th>
                <th className="table-header-cell">SKU</th>
                <th className="table-header-cell">Category</th>
                <th className="table-header-cell">Price</th>
                <th className="table-header-cell">Cost</th>
                <th className="table-header-cell">Stock</th>
                <th className="table-header-cell">Status</th>
                <th className="table-header-cell text-right">Actions</th>
              </tr>
            </thead>
            <tbody className="bg-card divide-y divide-border">
              {filteredProducts.map((product) => {
                const isLowStock = product.trackInventory && product.stock <= product.minStock;
                const isOutOfStock = product.trackInventory && product.stock === 0;
                
                const image = thumbnail(product);
                return (
                  <tr key={product.id} className="table-row cursor-pointer" onClick={() => handleEditProduct(product)}>
                    <td className="table-cell">
                      <div className="flex items-center">
                        <div className="h-10 w-10 bg-lightgray rounded-xl flex items-center justify-center flex-shrink-0 overflow-hidden">
                          {image ? (
                            <img src={image} alt="" className="h-full w-full object-cover" loading="lazy" />
                          ) : (
                            <Package className="h-5 w-5 text-bodytext" />
                          )}
                        </div>
                        <div className="ml-4 min-w-0 max-w-[320px]">
                          <div className="flex items-center gap-2 min-w-0">
                            <button type="button" className="text-sm font-semibold text-link truncate text-left hover:text-primary hover:underline" title={productLabel(product)}
                                    onClick={event => { event.stopPropagation(); handleEditProduct(product); }}>{productLabel(product)}</button>
                            {publishedIds.has(product.styleId) && <span className="flex-shrink-0 text-xs rounded-full bg-lightsuccess text-success px-2 py-1">Online</span>}
                          </div>
                          <div className="text-xs text-bodytext truncate" title={product.description}>{product.description}</div>
                        </div>
                      </div>
                    </td>
                    <td className="table-cell font-mono text-xs"><span className="block max-w-[180px] truncate" title={product.sku}>{product.sku}</span></td>
                    <td className="table-cell">
                      <span className="badge badge-info max-w-[180px] truncate inline-block align-middle" title={product.category}>{product.category.split(">").pop()?.trim() || product.category}</span>
                    </td>
                    <td className="table-cell font-semibold">
                      {state.settings.currency} {product.price.toFixed(2)}
                    </td>
                    <td className="table-cell text-bodytext">
                      {state.settings.currency} {product.cost.toFixed(2)}
                    </td>
                    <td className="table-cell">
                      <div className="flex items-center space-x-2">
                        <span className={`font-medium ${
                          isOutOfStock ? 'text-error' : isLowStock ? 'text-warning' : 'text-link'
                        }`}>
                          {product.stock}
                        </span>
                        {isLowStock && (
                          <AlertTriangle className="h-4 w-4 text-warning" />
                        )}
                      </div>
                    </td>
                    <td className="table-cell">
                      <span className={`badge ${
                        isOutOfStock
                          ? 'badge-danger'
                          : isLowStock
                          ? 'badge-warning'
                          : 'badge-success'
                      }`}>
                        {isOutOfStock ? 'Out of Stock' : isLowStock ? 'Low Stock' : 'In Stock'}
                      </span>
                    </td>
                    <td className="table-cell text-right" onClick={event => event.stopPropagation()}>
                      <DropdownMenu><DropdownMenuTrigger asChild><button className="header-action" aria-label="Product actions"><MoreHorizontal size={20}/></button></DropdownMenuTrigger><DropdownMenuContent align="end" className="bg-card p-2">
                        {product.trackInventory && (
                          <DropdownMenuItem asChild><button
                            onClick={() => setAdjustingProduct(product)}
                            className="flex w-full items-center gap-2 text-sm text-bodytext hover:text-link p-2 rounded-lg hover:bg-lightgray transition-colors"
                          >
                            <Boxes className="h-4 w-4" /> Adjust stock
                          </button></DropdownMenuItem>
                        )}
                        {product.kind !== 'service' && (
                          <DropdownMenuItem asChild><button
                            onClick={() => setLabelItems([product])}
                            className="flex w-full items-center gap-2 text-sm text-bodytext hover:text-link p-2 rounded-lg hover:bg-lightgray transition-colors"
                          >
                            <Tag className="h-4 w-4" /> Print labels
                          </button></DropdownMenuItem>
                        )}
                        <DropdownMenuItem asChild><button
                          onClick={() => handleEditProduct(product)}
                          className="flex w-full items-center gap-2 text-sm text-primary hover:text-primary p-2 rounded-lg hover:bg-lightprimary transition-colors"
                        >
                          <Edit className="h-4 w-4" /> Edit style
                        </button></DropdownMenuItem>
                        <DropdownMenuItem asChild><button
                          onClick={() => handleDeleteProduct(product.id)}
                          className="flex w-full items-center gap-2 text-sm text-error hover:text-error p-2 rounded-lg hover:bg-lighterror transition-colors"
                        >
                          <Trash2 className="h-4 w-4" /> Remove from sale
                        </button></DropdownMenuItem>
                      </DropdownMenuContent></DropdownMenu>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </DataTable>
        </div>
      </div>

      <div className="flex gap-3 items-center text-sm">
        <span>Showing {products.length ? page * 50 + 1 : 0}–{products.length ? page * 50 + products.length : 0} of {query.data?.total ?? 0}</span>
        <button type="button" className="btn btn-secondary btn-sm" disabled={!page || query.searching} onClick={() => setPage(page - 1)}>Previous</button>
        <button type="button" className="btn btn-secondary btn-sm" disabled={query.searching || (page + 1) * 50 >= (query.data?.total ?? 0)} onClick={() => setPage(page + 1)}>Next</button>
      </div>
      </>
      )}

      <StyleModal
        isOpen={showStyleModal}
        onClose={() => setShowStyleModal(false)}
        styleId={editingStyleId}
        initialCategory={newStyleCategory(department, selectedCategory)}
        department={department}
      />
      <StockAdjustModal product={adjustingProduct} onClose={() => setAdjustingProduct(null)} />
      <LabelPrintModal isOpen={!!labelItems} initial={labelItems ?? []} onClose={() => setLabelItems(null)} />
    </div>
  );
}
