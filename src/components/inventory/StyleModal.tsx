import { shopCategoryNames, sectionOfCategory, sectionById } from '../../../shared/bicycles';
import { departmentCategories, type Department } from '../../lib/inventoryCategory';
import { BikeVariantBuilder } from './BikeVariantBuilder';
import { uniqueOptions, missingVariants, duplicateVariantError } from '../../lib/variantOptions';
import { ComboInput } from '@/components/shared/ComboInput';
import { applyVariantAmount } from '../../lib/variantPricing';
import { useBusinessLookups } from '../../lib/lookups';
import {Input}from'@/components/ui/input';
import {DataTable}from'@/components/shared/DataTable';
import {ModalShell}from'@/components/shared/ModalShell';
import { useApp } from '../../context/SupabaseAppContext';
import { WebsitePanel } from './WebsitePanel';
import { useProductCategories } from '../../lib/hooks/useProducts';
import { queryKeys } from '../../lib/queryClient';
import React, { useEffect, useState } from 'react';
import { X, Plus, Trash2 } from 'lucide-react';
import { useQuery } from '@tanstack/react-query';
import { ProductKind } from '../../types';
import { stylesService, StyleInput, StyleVariantInput } from '../../lib/services';
import { swalConfig } from '../../lib/sweetAlert';
import { getErrorMessage } from '../../lib/errors';


interface StyleModalProps {
  isOpen: boolean;
  onClose: () => void;
  styleId: string | null;
  initialCategory?: string;
  department?: Department;
}

const KINDS: { value: ProductKind; label: string; priceLabel: string; stockUnit: string }[] = [
  { value: 'garment', label: 'Ready-made item', priceLabel: 'Price', stockUnit: 'pcs' },
  { value: 'pack', label: 'Pack or multipack', priceLabel: 'Price per pack', stockUnit: 'packs' },
  { value: 'service', label: 'Service (no stock)', priceLabel: 'Charge', stockUnit: '' },
];

type Row = StyleVariantInput & { key: string };

const emptyStyle: Omit<StyleInput, 'variants'> = {
  kind: 'garment',
  code: '',
  name: '',
  category: '',
  brand: '',
  material: '',
  season: '',
  designCode: '',
  description: '',
  sizeScheme: '',
  image: '',
  taxable: true,
  active: true,
  trackInventory: true,
};

const splitList = (value: string) =>
  value.split(',').map(v => v.trim()).filter(Boolean);

let rowCounter = 0;
const newKey = () => `row-${++rowCounter}`;

// One style with all its sizes and colors. Each row is a sellable item with
// its own SKU, barcode, price and stock.
export function StyleModal({ isOpen, onClose, styleId, initialCategory, department }: StyleModalProps) {
  const { state } = useApp();
  const websiteAllowed = ['admin', 'manager'].includes(state.currentUser?.role ?? '');
  const [tab, setTab] = useState<'details' | 'website'>('details');
  const [style, setStyle] = useState(emptyStyle);
  const [rows, setRows] = useState<Row[]>([]);
  const [selectedSizes, setSelectedSizes] = useState<string[]>([]);
  const [extraSizes, setExtraSizes] = useState('');
  const [colors, setColors] = useState('');
  const [fits, setFits] = useState('');
  const [defaultPrice, setDefaultPrice] = useState('');
  const [defaultCost, setDefaultCost] = useState('');
  const [bulkStatus, setBulkStatus] = useState('');
  const [saving, setSaving] = useState(false);
  const [loading, setLoading] = useState(false);

  const { data: schemes = [] } = useQuery({
    queryKey: queryKeys.sizeSchemes,
    queryFn: () => stylesService.getSizeSchemes(),
    enabled: isOpen,
    staleTime: 0,
  });

  useEffect(() => {
    if (!isOpen) return;
    setTab('details');
    setBulkStatus('');
    let cancelled = false;
    setSelectedSizes([]);
    setExtraSizes('');
    setColors('');
    setFits('');
    setDefaultPrice('');
    setDefaultCost('');
    if (!styleId) {
      setLoading(false);
      setStyle({ ...emptyStyle, category: initialCategory ?? '' });
      setRows([]);
      return;
    }
    setLoading(true);
    stylesService.get(styleId)
      .then(loaded => {
        if (cancelled) return;
        const { variants, ...rest } = loaded;
        setStyle({ ...emptyStyle, ...rest });
        setDefaultPrice(variants[0] ? String(variants[0].price) : '');
        setDefaultCost(variants[0]?.cost == null ? '' : String(variants[0].cost));
        setRows(variants.map(v => ({ ...v, key: newKey() })));
      })
      .catch(error => { if (!cancelled) swalConfig.error(`Could not load the style: ${getErrorMessage(error)}`); })
      .finally(() => { if (!cancelled) setLoading(false); });
    return () => { cancelled = true; };
  }, [isOpen, styleId, initialCategory]);

  const catalogLookups = useBusinessLookups(isOpen);
  const categoryQuery = useProductCategories(isOpen);
  const categories = uniqueOptions([...shopCategoryNames(), ...(categoryQuery.data ?? [])]);
  const categoryOptions = categories.map(value => ({ value, hint: sectionOfCategory(value)?.label }));

  if (!isOpen) return null;

  const kind = KINDS.find(k => k.value === style.kind) ?? KINDS[0];
  const isGarment = style.kind === 'garment';
  const section = sectionOfCategory(style.category);
  const isService = style.kind === 'service';
  const scheme = schemes.find(s => s.code === style.sizeScheme);

  const setField = (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement>) => {
    const { name, value, type } = e.target;
    setStyle(prev => ({ ...prev, [name]: type === 'checkbox' ? (e.target as HTMLInputElement).checked : value }));
  };
  const setText = (name: 'category' | 'brand' | 'material' | 'season') => (value: string) =>
    setStyle(prev => ({ ...prev, [name]: value }));

  const updateRow = (key: string, changes: Partial<Row>) =>
    setRows(prev => prev.map(r => (r.key === key ? { ...r, ...changes } : r)));

  const toggleSize = (size: string) =>
    setSelectedSizes(prev => (prev.includes(size) ? prev.filter(s => s !== size) : [...prev, size]));

  // Adds every missing size x color x fit combination as a new row
  const buildRows = () => {
    if (!style.code.trim()) {
      swalConfig.warning('Enter the style code first; SKUs are built from it');
      return;
    }
    const sizes = isGarment ? [...selectedSizes, ...splitList(extraSizes)] : [];
    const colorList = isService ? [] : splitList(colors);
    const fitList = isGarment ? splitList(fits) : [];
    const added: Row[] = missingVariants(style.code, sizes, colorList, fitList, rows).map(variant => ({
      ...variant, key: newKey(), price: Number(defaultPrice || 0),
      cost: defaultCost === '' ? undefined : Number(defaultCost), active: true, openingStock: 0,
    }));
    if (added.length === 0) {
      swalConfig.info(rows.length ? 'All of these combinations are already listed' : 'Choose sizes or colors first');
      return;
    }
    setRows(prev => [...prev, ...added]);
  };

  const applyToAll = (field: 'price' | 'cost') => {
    const value = field === 'price' ? defaultPrice : defaultCost;
    try {
      const updated = applyVariantAmount(rows, field, value);
      if (!updated.length) { setBulkStatus('Add variant rows first.'); return; }
      setRows(updated);
      setBulkStatus(`${field === 'price' ? 'Price' : 'Cost'} updated on all ${updated.length} rows. Save changes to keep it.`);
    } catch (error) {
      setBulkStatus(getErrorMessage(error));
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!style.name.trim() || !style.code.trim()) {
      swalConfig.error('Style name and code are required');
      return;
    }
    const variants = rows;
    if (variants.length === 0) {
      swalConfig.error(isService ? 'Add a row with the charge' : 'Add at least one size or color');
      return;
    }
    const duplicate = duplicateVariantError(variants);
    if (duplicate) return swalConfig.error(duplicate);
    for (const r of variants) {
      if (!r.sku.trim()) return swalConfig.error('Every row needs a SKU');
      if (!Number.isFinite(r.price) || r.price < 0) return swalConfig.error(`Enter a valid price for ${r.sku}`);
      if (r.cost !== undefined && (!Number.isFinite(r.cost) || r.cost < 0)) return swalConfig.error('Enter a valid cost for ' + r.sku);
      const opening = r.openingStock ?? 0;
      if (!r.variantId && (!Number.isFinite(opening) || opening < 0 || !Number.isInteger(opening))) {
        return swalConfig.error(`Opening stock for ${r.sku} must be a whole number`);
      }
    }

    setSaving(true);
    try {
      await stylesService.save({
        ...style,
        code: style.code.trim(),
        name: style.name.trim(),
        sizeScheme: isGarment ? style.sizeScheme : undefined,
        trackInventory: !isService && style.trackInventory,
        variants: variants.map(({ key: _key, stock: _stock, ...v }) => v),
      });
      swalConfig.success(styleId ? 'Style updated' : 'Style added');
      onClose();
    } catch (error) {
      swalConfig.error(`Could not save: ${getErrorMessage(error)}`);
    } finally {
      setSaving(false);
    }
  };

  const handleImageUpload = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file || !file.type.startsWith('image/')) return;
    if (file.size > 1_000_000) {
      swalConfig.error('Please choose an image under 1 MB');
      return;
    }
    const reader = new FileReader();
    reader.onload = (event) => setStyle(prev => ({ ...prev, image: event.target?.result as string }));
    reader.readAsDataURL(file);
  };

  const label = (text: string) => <span className="block text-sm font-medium text-link mb-1">{text}</span>;

  return (
    <div className="modal-overlay">
      <ModalShell className="modal max-w-6xl">
        <div className="modal-header">
          <h2 className="text-xl font-bold text-link">{styleId ? `Edit ${style.name || 'style'}` : 'Add style'}</h2>
          <button onClick={onClose} className="text-bodytext hover:text-bodytext p-2 rounded-xl hover:bg-lightgray">
            <X className="h-6 w-6" />
          </button>
        </div>

        {websiteAllowed && <div className="flex gap-2 px-6 pt-3"><button type="button" className="btn btn-secondary btn-sm" onClick={() => setTab('details')}>Details</button><button type="button" className="btn btn-secondary btn-sm" onClick={() => setTab('website')}>Website</button></div>}
        {tab === 'website' && websiteAllowed ? <WebsitePanel styleId={styleId} /> : loading ? (
          <div className="modal-body text-center text-bodytext py-12">Loading…</div>
        ) : (
          <form onSubmit={handleSubmit}>
            <div className="modal-body space-y-6">
              {/* Style */}
              <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
                <label className="block md:col-span-2">
                  {label('Type *')}
                  <select name="kind" value={style.kind} onChange={setField} className="select" disabled={!!styleId}>
                    {KINDS.map(k => <option key={k.value} value={k.value}>{k.label}</option>)}
                  </select>
                </label>
                <label className="block">
                  {label('Style code *')}
                  <Input name="code" value={style.code} onChange={setField} className="input" required placeholder="e.g. BK-CTY-001" />
                </label>
                <div className="block">
                  {label('Category')}
                  <ComboInput aria-label="Category" name="category" value={style.category} onChange={setText('category')} className="input" options={categoryOptions} newLabel="category" />
                  {department && !departmentCategories(department).includes(style.category?.trim() ?? '') && (
                    <p role="status" className="text-xs text-warning mt-1">
                      Only {sectionById(department).label.toLowerCase()} categories show in this section. Choose one from the list, or this item will appear only in Inventory.
                    </p>
                  )}
                </div>
                <label className="block md:col-span-2">
                  {label('Name *')}
                  <Input name="name" value={style.name} onChange={setField} className="input" required
                         placeholder="e.g. Urban 7-Speed City Bike" />
                </label>
                <div className="block">
                  {label('Brand')}
                  <ComboInput aria-label="Brand" name="brand" value={style.brand} onChange={setText('brand')} className="input" options={catalogLookups.data?.brand || []} />
                </div>
                <div className="block">
                  {label('Frame / material')}
                  <ComboInput aria-label="Frame / material" name="material" value={style.material} onChange={setText('material')} className="input" options={catalogLookups.data?.material || []} placeholder="e.g. Aluminium, Steel, Carbon" />
                </div>
                <div className="block">
                  {label('Season / collection')}
                  <ComboInput aria-label="Season / collection" name="season" value={style.season} onChange={setText('season')} className="input" options={catalogLookups.data?.season || []} placeholder="e.g. 2027 range" />
                </div>
                <label className="block">
                  {label('Design code')}
                  <Input name="designCode" value={style.designCode} onChange={setField} className="input" />
                </label>
                <div className="md:col-span-2 flex items-end gap-4">
                  {style.image && <img src={style.image} alt="" className="h-12 w-12 rounded-lg object-cover" />}
                  <label className="block">
                    {label('Image')}
                    <Input type="file" accept="image/*" onChange={handleImageUpload} className="text-sm" />
                  </label>
                </div>
                <label className="block md:col-span-4">
                  {label('Description')}
                  <textarea name="description" value={style.description} onChange={setField} className="textarea" rows={2} />
                </label>
                <div className="md:col-span-4 flex flex-wrap gap-6">
                  <label className="flex items-center space-x-2">
                    <Input type="checkbox" name="taxable" checked={style.taxable} onChange={setField} />
                    <span className="text-sm text-link">Taxable</span>
                  </label>
                  <label className="flex items-center space-x-2">
                    <Input type="checkbox" name="active" checked={style.active} onChange={setField} />
                    <span className="text-sm text-link">For sale</span>
                  </label>
                  {!isService && (
                    <label className="flex items-center space-x-2">
                      <Input type="checkbox" name="trackInventory" checked={style.trackInventory} onChange={setField} />
                      <span className="text-sm text-link">Track stock</span>
                    </label>
                  )}
                </div>
              </div>

              {/* Matrix builder */}
              {!isService && (
                <div className="bg-lightgray rounded-xl p-4 space-y-4">
                  <h3 className="font-semibold text-link">
                    {isGarment ? 'Sizes and colours' : 'Colours / designs'}
                  </h3>
                  {isGarment && (
                    <div className="space-y-2">
                      {section && <BikeVariantBuilder category={style.category ?? ''} onSizes={sizes => setSelectedSizes(prev => uniqueOptions([...prev, ...sizes]))} onColours={values => setColors(prev => uniqueOptions([...splitList(prev), ...values]).join(', '))}/>}
                      {selectedSizes.length > 0 && <div className="flex flex-wrap gap-2" aria-label="Selected sizes">{selectedSizes.map(size => <button type="button" key={size} className="btn btn-secondary btn-sm" aria-label={'Remove size ' + size} onClick={() => toggleSize(size)}>{size} ×</button>)}</div>}
                      <div className="flex flex-wrap items-center gap-2">
                        <select aria-label="Saved size preset" name="sizeScheme" value={style.sizeScheme} onChange={setField} className="select w-56">
                          <option value="">No preset — enter sizes below</option>
                          {style.sizeScheme && !schemes.some(s => s.code === style.sizeScheme) && <option value={style.sizeScheme}>{style.sizeScheme} (inactive)</option>}
                          {schemes.map(s => <option key={s.code} value={s.code}>{s.name}</option>)}
                        </select>
                        {scheme?.sizes.map(size => (
                          <button key={size} type="button" aria-pressed={selectedSizes.includes(size)} onClick={() => toggleSize(size)}
                                  className={`px-3 py-1 rounded-lg border text-sm ${selectedSizes.includes(size)
                                    ? 'bg-primary text-white border-primary' : 'bg-card border-border text-link'}`}>
                            {size}
                          </button>
                        ))}
                      </div>
                      <Input aria-label="Other sizes" value={extraSizes} onChange={e => setExtraSizes(e.target.value)} className="input"
                             placeholder='Other sizes, comma separated (e.g. M, 54 cm, 20")' />
                    </div>
                  )}
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                    <ComboInput multiple aria-label="Colors, comma separated" value={colors} onChange={setColors} className="input"
                                options={catalogLookups.data?.color || []}
                                placeholder="Colours, comma separated (e.g. Black, Red, Blue)" />
                    {isGarment && (
                      <ComboInput multiple aria-label="Variants, comma separated" value={fits} onChange={setFits} className="input"
                                  options={catalogLookups.data?.fit || []}
                                  placeholder="Variants, optional (e.g. 21-speed, Disc brakes)" />
                    )}
                  </div>
                  <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-[1fr_1fr_auto] items-end gap-3">
                    <div className="min-w-0">
                      <label htmlFor="bulk-price" className="block text-sm font-medium text-link mb-1">Default {kind.priceLabel.toLowerCase()}</label>
                      <div className="flex flex-wrap sm:flex-nowrap gap-2">
                        <Input type="number" min="0" step="0.01" id="bulk-price" value={defaultPrice} onChange={e => { setDefaultPrice(e.target.value); setBulkStatus(''); }}
                               className="input min-w-0 flex-1" />
                        <button type="button" onClick={() => applyToAll('price')} className="btn btn-secondary btn-sm shrink-0" aria-label="Apply default price to all variants">Apply to all</button>
                      </div>
                    </div>
                    <div className="min-w-0">
                      <label htmlFor="bulk-cost" className="block text-sm font-medium text-link mb-1">Default cost</label>
                      <div className="flex flex-wrap sm:flex-nowrap gap-2">
                        <Input type="number" min="0" step="0.01" id="bulk-cost" value={defaultCost} onChange={e => { setDefaultCost(e.target.value); setBulkStatus(''); }}
                               className="input min-w-0 flex-1" />
                        <button type="button" onClick={() => applyToAll('cost')} className="btn btn-secondary btn-sm shrink-0" aria-label="Apply default cost to all variants">Apply to all</button>
                      </div>
                    </div>
                    <button type="button" onClick={buildRows} className="btn btn-primary btn-md">
                      <Plus className="h-4 w-4" />
                      <span>Add rows</span>
                    </button>
                  </div>
                </div>
              )}

              <p role="status" className="text-sm text-link">{bulkStatus}</p>

              {/* Rows */}
              <div className="overflow-x-auto">
                <DataTable className="table">
                  <thead className="table-header">
                    <tr>
                      {isGarment && <th className="table-header-cell">Size</th>}
                      {!isService && <th className="table-header-cell">Colour</th>}
                      {isGarment && <th className="table-header-cell">Variant</th>}
                      <th className="table-header-cell">SKU</th>
                      {!isService && <th className="table-header-cell">Barcode</th>}
                      <th className="table-header-cell">{kind.priceLabel}</th>
                      <th className="table-header-cell">Cost</th>
                      {!isService && <th className="table-header-cell">Stock ({kind.stockUnit})</th>}
                      <th className="table-header-cell">For sale</th>
                      <th className="table-header-cell" />
                    </tr>
                  </thead>
                  <tbody className="bg-card divide-y divide-border">
                    {rows.length === 0 && (
                      <tr>
                        <td colSpan={10} className="table-cell text-center text-bodytext py-6">
                          {isService ? 'Add a row for the charge.' : 'Choose sizes and colors above, then "Add rows".'}
                        </td>
                      </tr>
                    )}
                    {rows.map(r => (
                      <tr key={r.key}>
                        {isGarment && (
                          <td className="table-cell">
                            <Input value={r.size || ''} onChange={e => updateRow(r.key, { size: e.target.value })} className="input w-20" />
                          </td>
                        )}
                        {!isService && (
                          <td className="table-cell">
                            <Input value={r.color || ''} onChange={e => updateRow(r.key, { color: e.target.value })} className="input w-28" />
                          </td>
                        )}
                        {isGarment && (
                          <td className="table-cell">
                            <Input value={r.fit || ''} onChange={e => updateRow(r.key, { fit: e.target.value })} className="input w-24" />
                          </td>
                        )}
                        <td className="table-cell">
                          <Input value={r.sku} onChange={e => updateRow(r.key, { sku: e.target.value })} className="input w-40 font-mono" />
                        </td>
                        {!isService && (
                          <td className="table-cell">
                            <Input value={r.barcode || ''} onChange={e => updateRow(r.key, { barcode: e.target.value })}
                                   className="input w-36" placeholder="Scan" />
                          </td>
                        )}
                        <td className="table-cell">
                          <Input type="number" min="0" step="0.01" value={r.price}
                                 onChange={e => updateRow(r.key, { price: Number(e.target.value) })} className="input w-28" />
                        </td>
                        <td className="table-cell">
                          <Input type="number" min="0" step="0.01" value={r.cost ?? ''}
                                 onChange={e => updateRow(r.key, { cost: e.target.value === '' ? undefined : Number(e.target.value) })}
                                 className="input w-28" />
                        </td>
                        {!isService && (
                          <td className="table-cell">
                            {r.variantId ? (
                              <span className="text-link">{r.stock ?? 0}</span>
                            ) : (
                              <Input type="number" min="0" step="1" value={r.openingStock ?? 0}
                                     onChange={e => updateRow(r.key, { openingStock: Number(e.target.value) })}
                                     className="input w-24" title="Opening stock" />
                            )}
                          </td>
                        )}
                        <td className="table-cell">
                          <Input type="checkbox" checked={r.active} onChange={e => updateRow(r.key, { active: e.target.checked })} />
                        </td>
                        <td className="table-cell">
                          {!r.variantId && (
                            <button type="button" onClick={() => setRows(prev => prev.filter(x => x.key !== r.key))}
                                    className="text-error hover:text-error p-1">
                              <Trash2 className="h-4 w-4" />
                            </button>
                          )}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </DataTable>
                {isService && rows.length === 0 && (
                  <button type="button" className="btn btn-secondary btn-sm mt-3"
                          onClick={() => setRows([{ key: newKey(), sku: style.code.toUpperCase() || 'SERVICE', price: 0, active: true }])}>
                    <Plus className="h-4 w-4" /><span>Add charge row</span>
                  </button>
                )}
                <p className="text-xs text-bodytext mt-2">
                  Existing rows show current stock. To change it, use "Adjust stock" in the inventory list (a reason is recorded).
                </p>
              </div>
            </div>

            <div className="modal-footer">
              <button type="button" onClick={onClose} className="btn btn-secondary btn-md" disabled={saving}>Cancel</button>
              <button type="submit" className="btn btn-primary btn-md" disabled={saving}>
                {saving ? 'Saving...' : styleId ? 'Save changes' : 'Add style'}
              </button>
            </div>
          </form>
        )}
      </ModalShell>
    </div>
  );
}
