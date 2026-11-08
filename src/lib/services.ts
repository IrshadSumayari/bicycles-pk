import type { ProductGuide } from '../../shared/productGuide';
import { tryOnLimits, type TryOn } from '../../shared/tryOn';
import type { LingerieAttributes } from '../../shared/lingerie';
import { platformStoreName, platformReceiptText, platformStoreEmail } from './branding';
import type { OpeningBalance } from './goLiveImport'
import type { OnlineOrder, OnlineOrderRow } from './onlineOrders'
import { customerSearchFilter, customerSearchTerm } from './customerSearch'
import { FunctionsHttpError } from '@supabase/supabase-js'
import { supabase } from './supabase'
import { Database, Json } from './database.types'
import { Product, Customer, Sale, Discount, User, AppSettings, SalesTab, CartItem } from '../types'
import { queryClient, queryKeys, invalidateProducts, invalidateTransactions, invalidateShifts } from './queryClient'

export type ReportGroup = 'style' | 'variant' | 'category' | 'size' | 'color'

export const onlineOrdersService = {
  async list(p: { status?: string; q?: string; limit?: number; offset?: number } = {}) {
    const { data, error } = await supabase.rpc('list_online_orders', { p })
    if (error) throw error
    return data as unknown as { orders: OnlineOrderRow[]; total_count: number }
  },
  async detail(id: string) {
    const { data, error } = await supabase.rpc('online_order_detail', { p_id: id })
    if (error) throw error
    return data as unknown as OnlineOrder
  },
  async locations() {
    const { data, error } = await supabase.from('locations').select('id,name,code').order('code')
    if (error) throw error
    return data ?? []
  },
  async advance(p: Json) {
    const { error } = await supabase.rpc('advance_online_order', { p })
    if (error) throw error
  },
  async collect(p: Json) {
    const { error } = await supabase.rpc('collect_cod_payment', { p })
    if (error) throw error
  },
  async cancel(p: Json) {
    const { error } = await supabase.rpc('cancel_online_order', { p })
    if (error) throw error
  },
  async parcelReturn(orderId: string) {
    const { data, error } = await supabase.from('courier_returns').select('reason,courier_cost').eq('order_id', orderId).single()
    if (error) throw error
    return data
  },
  async receiveParcel(p: Json) {
    const { data, error } = await supabase.rpc('receive_cod_parcel_return', { p })
    if (error) throw error
    return data
  },
  async refund(p: Json) {
    const { error } = await supabase.rpc('record_online_refund', { p })
    if (error) throw error
  },
  async check(orderNo: string) {
    const { data, error } = await supabase.functions.invoke('payment-check', { body: { orderNo } })
    if (error) {
      if (error instanceof FunctionsHttpError) {
        const body = await error.context.json().catch(() => null)
        if (body?.error) throw new Error(body.error)
      }
      throw error
    }
    return data
  },
}

// RPC table responses have the same API row cap as regular selects. Fetch
// every page so long date ranges and large catalogs are not silently cut off.
async function reportRows<T>(page: (from: number, to: number) => PromiseLike<{ data: T[] | null; error: unknown }>): Promise<T[]> {
  const rows: T[] = []
  for (let offset = 0; ; offset += 1000) {
    const { data, error } = await page(offset, offset + 999)
    if (error) throw error
    rows.push(...(data ?? []))
    if (!data || data.length < 1000) return rows
  }
}

// Read typed ledger reports. An omitted branch means all permitted branches.
export const reportsService = {
  async salesSummary(from: string, to: string, branchId?: string) {
    return reportRows((start, end) => supabase.rpc('report_sales_summary', { p_from: from, p_to: to, p_branch: branchId }).range(start, end))
  },
  async tenders(from: string, to: string, branchId?: string) {
    return reportRows((start, end) => supabase.rpc('report_tenders', { p_from: from, p_to: to, p_branch: branchId }).range(start, end))
  },
  async topItems(from: string, to: string, group: ReportGroup, limit = 50, branchId?: string) {
    return reportRows((start, end) => supabase.rpc('report_top_items', {
      p_from: from, p_to: to, p_branch: branchId, p_group: group, p_limit: limit,
    }).range(start, end))
  },
  async sizeColorMatrix(from: string, to: string, styleId: string, branchId?: string) {
    return reportRows((start, end) => supabase.rpc('report_size_color_matrix', {
      p_from: from, p_to: to, p_branch: branchId, p_style: styleId,
    }).range(start, end))
  },
  async staffSales(from: string, to: string, branchId?: string) {
    return reportRows((start, end) => supabase.rpc('report_staff_sales', { p_from: from, p_to: to, p_branch: branchId }).range(start, end))
  },
}

// Products Service
// Reads sellable variants from the catalog with their shop-floor stock.
// Costs come from variant_costs, which only managers and admins can read.
const VARIANT_SELECT = `
  id, sku, size, color, fit, price, min_stock, active, created_at, updated_at,
  style:product_styles!inner (
    id, name, kind, unit, taxable, track_inventory, active, description, image_url,
    category:categories ( name )
  ),
  barcodes ( code ),
  stock:stock_balances ( location_id, on_hand, reserved )
`

type VariantRow = {
  id: string
  sku: string
  size: string | null
  color: string | null
  fit: string | null
  price: number
  min_stock: number
  active: boolean
  created_at: string
  updated_at: string
  style: {
    id: string
    name: string
    kind: string
    unit: string
    taxable: boolean
    track_inventory: boolean
    active: boolean
    description: string | null
    image_url: string | null
    category: { name: string } | null
  }
  barcodes: { code: string }[]
  stock: { location_id: string; on_hand: number; reserved: number }[]
}

let sellingLocationId: string | null = null

// The shop floor of the default branch: where the POS sells from
export async function getSellingLocationId(): Promise<string | null> {
  if (sellingLocationId) return sellingLocationId
  const { data } = await supabase
    .from('locations')
    .select('id')
    .eq('kind', 'shop_floor')
    .eq('active', true)
    .order('created_at')
    .limit(1)
    .maybeSingle()
  sellingLocationId = data?.id ?? null
  return sellingLocationId
}

function mapVariant(row: VariantRow, costs: Map<string, number>, locationId: string | null): Product {
  const kind = row.style.kind as Product['kind']
  const floor = row.stock.find(s => s.location_id === locationId)
  const available = floor ? Number(floor.on_hand) - Number(floor.reserved) : 0
  return {
    id: row.id,
    styleId: row.style.id,
    kind,
    name: row.style.name,
    size: row.size || undefined,
    color: row.color || undefined,
    fit: row.fit || undefined,
    sku: row.sku,
    barcode: row.barcodes[0]?.code,
    barcodes: row.barcodes.map(b => b.code),
    price: Number(row.price),
    cost: costs.get(row.id) ?? 0,
    stock: row.style.track_inventory ? available : 0,
    minStock: Number(row.min_stock),
    category: row.style.category?.name || '',
    description: row.style.description || '',
    image: row.style.image_url || undefined,
    taxable: row.style.taxable,
    active: row.active && row.style.active,
    createdAt: new Date(row.created_at),
    updatedAt: new Date(row.updated_at),
    unit: row.style.unit,
    trackInventory: row.style.track_inventory,
  }
}

async function loadCosts(variantIds?: string[]): Promise<Map<string, number>> {
  let query = supabase.from('variant_costs').select('variant_id, unit_cost')
  if (variantIds) query = query.in('variant_id', variantIds)
  const { data } = await query
  return new Map((data || []).map(c => [c.variant_id, Number(c.unit_cost)]))
}

export type ProductSort = 'name' | 'updated' | 'newest'
export interface ProductSearchParams {
  q?: string; category?: string; categories?: string[]; kind?: Product['kind']; activeOnly?: boolean;
  limit?: number; offset?: number; locationId?: string; withCosts?: boolean;
  // Server order: name (default), most recently edited, or newest added first
  sort?: ProductSort;
}
type CatalogRow = Database['public']['Functions']['search_variants']['Returns'][number]
function mapCatalogProduct(row: CatalogRow, costs = new Map<string, number>()): Product {
  return {
    id: row.variant_id, styleId: row.style_id, sku: row.sku, name: row.name,
    size: row.size || undefined, color: row.color || undefined, fit: row.fit || undefined,
    kind: row.kind as Product['kind'], unit: row.unit,
    price: Number(row.price), cost: costs.get(row.variant_id) ?? 0,
    stock: Number(row.available), minStock: Number(row.min_stock),
    active: row.active, taxable: row.taxable, trackInventory: row.track_inventory,
    category: row.category, description: row.description, image: row.image || undefined,
    createdAt: new Date(row.created_at), updatedAt: new Date(row.updated_at),
    barcodes: row.barcodes, barcode: row.barcode || undefined,
  }
}

export const productsService = {
  async search(params: ProductSearchParams = {}) {
    const { data, error } = await supabase.rpc('search_variants', { p: {
      q: params.q, category: params.category, categories: params.categories, kind: params.kind, limit: params.limit ?? 60,
      offset: params.offset ?? 0, active_only: params.activeOnly ?? true, location_id: params.locationId, sort: params.sort,
    } })
    if (error) throw error
    const costs = params.withCosts && data.length ? await loadCosts(data.map(row => row.variant_id)) : new Map<string, number>()
    return { rows: data.map(row => mapCatalogProduct(row, costs)), total: Number(data[0]?.total_count ?? 0) }
  },
  async byCode(code: string): Promise<Product | null> {
    const { data, error } = await supabase.rpc('variant_by_code', { p_code: code.trim() })
    if (error) throw error
    return data[0] ? mapCatalogProduct(data[0]) : null
  },
  async categories(): Promise<string[]> {
    const { data, error } = await supabase.from('categories').select('name').eq('active', true).order('name')
    if (error) throw error
    return data.map(row => row.name)
  },
  async identifiers() {
    const skus: string[] = [], barcodes: string[] = []
    for (let offset = 0; ; offset += 1000) {
      const { data, error } = await supabase.from('product_variants').select('sku').order('id').range(offset, offset + 999)
      if (error) throw error
      skus.push(...data.map(row => row.sku))
      if (data.length < 1000) break
    }
    for (let offset = 0; ; offset += 1000) {
      const { data, error } = await supabase.from('barcodes').select('code').order('code').range(offset, offset + 999)
      if (error) throw error
      barcodes.push(...data.map(row => row.code))
      if (data.length < 1000) break
    }
    return { skus, barcodes }
  },
  async getByIds(ids: string[]): Promise<Product[]> {
    if (!ids.length) return []
    const location = await getSellingLocationId()
    const rows: Product[] = []
    for (let offset = 0; offset < ids.length; offset += 200) {
      const { data, error } = await supabase.from('product_variants').select(VARIANT_SELECT).in('id', ids.slice(offset, offset + 200))
      if (error) throw error
      rows.push(...(data as unknown as VariantRow[]).map(row => mapVariant(row, new Map(), location)))
    }
    return rows
  },

  async getById(id: string): Promise<Product> {
    const [locationId, variant, costs] = await Promise.all([
      getSellingLocationId(),
      supabase.from('product_variants').select(VARIANT_SELECT).eq('id', id).single(),
      Promise.resolve(new Map<string, number>()),
    ])
    if (variant.error) throw variant.error
    return mapVariant(variant.data as unknown as VariantRow, costs, locationId)
  },

  // Stock changes go through the ledger with a reason
  async adjustStock(variantId: string, quantity: number, reason: string): Promise<void> {
    const locationId = await getSellingLocationId()
    if (!locationId) throw new Error('No shop floor location found')
    const { error } = await supabase.rpc('adjust_stock', {
      p_variant_id: variantId,
      p_location_id: locationId,
      p_quantity: quantity,
      p_reason: reason,
      p_movement_type: 'adjust',
      p_request_id: crypto.randomUUID(),
    })
    if (error) throw error
    invalidateProducts()
  },

  // Items with sales history are kept and hidden instead of deleted
  async delete(id: string): Promise<void> {
    const { error } = await supabase.from('product_variants').update({ active: false }).eq('id', id)
    if (error) throw error
    invalidateProducts()
  }
}

// Styles Service: a style with all its size / color / fit variants
export interface StyleVariantInput {
  braBand?: string
  braCup?: string
  variantId?: string
  sku: string
  size?: string
  color?: string
  fit?: string
  price: number
  cost?: number
  barcode?: string
  minStock?: number
  active: boolean
  openingStock?: number
  // Read-only, for display when editing
  stock?: number
}

export interface StyleInput {
  lingerie?: LingerieAttributes
  styleId?: string
  kind: Product['kind']
  code: string
  name: string
  category?: string
  brand?: string
  material?: string
  season?: string
  designCode?: string
  description?: string
  sizeScheme?: string
  image?: string
  taxable: boolean
  active: boolean
  trackInventory: boolean
  variants: StyleVariantInput[]
}

export interface SizeScheme {
  code: string
  name: string
  sizes: string[]
}

type StyleRow = {
  lingerie: LingerieAttributes
  id: string
  code: string
  name: string
  kind: string
  brand: string | null
  material: string | null
  season: string | null
  design_code: string | null
  description: string | null
  taxable: boolean
  active: boolean
  track_inventory: boolean
  image_url: string | null
  category: { name: string } | null
  size_scheme: { code: string } | null
  variants: {
    bra_band: string | null
    bra_cup: string | null
    id: string
    sku: string
    size: string | null
    color: string | null
    fit: string | null
    price: number
    min_stock: number
    active: boolean
    barcodes: { code: string }[]
    stock: { location_id: string; on_hand: number; reserved: number }[]
  }[]
}

export const stylesService = {
  async listOptions(): Promise<{ id: string; code: string; name: string }[]> {
    const rows: { id: string; code: string; name: string }[] = []
    for (let offset = 0; ; offset += 1000) {
      const { data, error } = await supabase.from('product_styles').select('id, code, name')
        .order('name').order('id').range(offset, offset + 999)
      if (error) throw error
      rows.push(...data)
      if (data.length < 1000) return rows
    }
  },

  async listCodes(): Promise<string[]> {
    const rows: string[] = []
    for (let offset = 0; ; offset += 1000) {
      const { data, error } = await supabase.from('product_styles').select('code').order('id').range(offset, offset + 999)
      if (error) throw error
      rows.push(...data.map(row => row.code))
      if (data.length < 1000) return rows
    }
  },

  async getSizeSchemes(): Promise<SizeScheme[]> {
    const { data, error } = await supabase.from('size_schemes').select('code, name, sizes').eq('active', true).order('name')
    if (error) throw error
    return data
  },

  async get(styleId: string): Promise<StyleInput> {
    const [locationId, style] = await Promise.all([
      getSellingLocationId(),
      supabase
        .from('product_styles')
        .select(`
          id, code, name, kind, brand, material, season, design_code, description, taxable, active,
          track_inventory, image_url, lingerie,
          category:categories ( name ),
          size_scheme:size_schemes ( code ),
          variants:product_variants ( id, sku, size, color, fit, price, min_stock, active, bra_band, bra_cup,
            barcodes ( code ), stock:stock_balances ( location_id, on_hand, reserved ) )
        `)
        .eq('id', styleId)
        .single(),
    ])
    if (style.error) throw style.error
    const row = style.data as unknown as StyleRow
    const costs = await loadCosts(row.variants.map(v => v.id))
    return {
      lingerie: row.lingerie,
      styleId: row.id,
      kind: row.kind as Product['kind'],
      code: row.code,
      name: row.name,
      category: row.category?.name,
      brand: row.brand ?? undefined,
      material: row.material ?? undefined,
      season: row.season ?? undefined,
      designCode: row.design_code ?? undefined,
      description: row.description ?? undefined,
      sizeScheme: row.size_scheme?.code,
      image: row.image_url ?? undefined,
      taxable: row.taxable,
      active: row.active,
      trackInventory: row.track_inventory,
      variants: row.variants
        .map(v => {
          const floor = v.stock.find(s => s.location_id === locationId)
          return {
            braBand: v.bra_band ?? undefined,
            braCup: v.bra_cup ?? undefined,
            variantId: v.id,
            sku: v.sku,
            size: v.size ?? undefined,
            color: v.color ?? undefined,
            fit: v.fit ?? undefined,
            price: Number(v.price),
            cost: costs.get(v.id),
            barcode: v.barcodes[0]?.code,
            minStock: Number(v.min_stock),
            active: v.active,
            stock: floor ? Number(floor.on_hand) - Number(floor.reserved) : 0,
          }
        })
        .sort((a, b) => a.sku.localeCompare(b.sku)),
    }
  },

  // Creates or updates the style and every listed variant in one transaction
  async save(input: StyleInput): Promise<string> {
    const { data, error } = await supabase.rpc('save_style', {
      p: {
        ...(input.lingerie === undefined ? {} : { lingerie: input.lingerie }),
        style_id: input.styleId ?? null,
        kind: input.kind,
        code: input.code,
        name: input.name,
        category: input.category ?? null,
        brand: input.brand ?? null,
        material: input.material ?? null,
        season: input.season ?? null,
        design_code: input.designCode ?? null,
        description: input.description ?? null,
        size_scheme: input.sizeScheme ?? null,
        image_url: input.image ?? null,
        taxable: input.taxable,
        active: input.active,
        track_inventory: input.trackInventory,
        variants: input.variants.map(v => ({
          ...(v.braBand === undefined && v.braCup === undefined ? {} : { bra_band: v.braBand ?? null, bra_cup: v.braCup ?? null }),
          variant_id: v.variantId ?? null,
          sku: v.sku,
          size: v.size ?? null,
          color: v.color ?? null,
          fit: v.fit ?? null,
          price: v.price,
          cost: v.cost ?? null,
          barcode: v.barcode ?? null,
          min_stock: v.minStock ?? 0,
          active: v.active,
          opening_stock: v.variantId ? null : v.openingStock ?? 0,
        })),
      } as unknown as Json,
    })
    if (error) throw error
    invalidateProducts()
    void queryClient.invalidateQueries({ queryKey: queryKeys.webCatalog })
    return data as string
  },
}

// Suppliers and goods receiving
export interface Supplier {
  id: string
  name: string
  phone?: string
}

export interface GoodsReceiptLineInput {
  variantId: string
  quantity: number
  unitCost: number
}

export interface GoodsReceipt {
  id: string
  receiptNo: string
  supplierName?: string
  supplierReference?: string
  totalCost: number
  receivedAt: Date
  lines: { description: string; quantity: number; unitCost: number; lineCost: number }[]
}

export const suppliersService = {
  async list(): Promise<Supplier[]> {
    const { data, error } = await supabase.from('suppliers').select('id, name, phone').order('name')
    if (error) throw error
    return data.map(s => ({ id: s.id, name: s.name, phone: s.phone ?? undefined }))
  },
}

export const receiptsService = {
  async list(limit = 20): Promise<GoodsReceipt[]> {
    const { data, error } = await supabase
      .from('goods_receipts')
      .select('id, receipt_no, supplier_name, supplier_reference, total_cost, received_at, lines:goods_receipt_lines ( line_no, description, quantity, unit_cost, line_cost )')
      .order('received_at', { ascending: false })
      .limit(limit)
    if (error) throw error
    return data.map(r => ({
      id: r.id,
      receiptNo: r.receipt_no,
      supplierName: r.supplier_name ?? undefined,
      supplierReference: r.supplier_reference ?? undefined,
      totalCost: Number(r.total_cost),
      receivedAt: new Date(r.received_at),
      lines: [...r.lines]
        .sort((a, b) => a.line_no - b.line_no)
        .map(l => ({
          description: l.description,
          quantity: Number(l.quantity),
          unitCost: Number(l.unit_cost),
          lineCost: Number(l.line_cost),
        })),
    }))
  },

  // Posts a delivery in one transaction; a retry with the same requestId is safe
  async post(input: {
    requestId: string
    supplierId?: string
    supplierName?: string
    supplierReference?: string
    notes?: string
    lines: GoodsReceiptLineInput[]
  }): Promise<string> {
    const { data, error } = await supabase.rpc('post_goods_receipt', {
      p: {
        request_id: input.requestId,
        supplier_id: input.supplierId ?? null,
        supplier_name: input.supplierName ?? null,
        supplier_reference: input.supplierReference ?? null,
        notes: input.notes ?? null,
        lines: input.lines.map(l => ({
          variant_id: l.variantId,
          quantity: l.quantity,
          unit_cost: l.unitCost,
        })),
      } as unknown as Json,
    })
    if (error) throw error
    invalidateProducts()
    return (data as unknown as { receipt: { receipt_no: string } }).receipt.receipt_no
  },
}

// Stock counts
export interface StockCount {
  id: string
  countNo: string
  status: 'open' | 'approved' | 'cancelled'
  notes?: string
  createdAt: Date
  closedAt?: Date
}

export interface StockCountLine {
  id: string
  variantId: string
  counted: number
  expected: number
  difference?: number
  countedAt: Date
}

type CountRow = {
  id: string
  count_no: string
  status: string
  notes: string | null
  created_at: string
  closed_at: string | null
}

function mapCount(c: CountRow): StockCount {
  return {
    id: c.id,
    countNo: c.count_no,
    status: c.status as StockCount['status'],
    notes: c.notes ?? undefined,
    createdAt: new Date(c.created_at),
    closedAt: c.closed_at ? new Date(c.closed_at) : undefined,
  }
}

export const countsService = {
  async list(limit = 10): Promise<StockCount[]> {
    const { data, error } = await supabase
      .from('stock_counts')
      .select('id, count_no, status, notes, created_at, closed_at')
      .order('created_at', { ascending: false })
      .limit(limit)
    if (error) throw error
    return data.map(mapCount)
  },

  async lines(countId: string): Promise<StockCountLine[]> {
    const { data, error } = await supabase
      .from('stock_count_lines')
      .select('id, variant_id, counted, expected, difference, counted_at')
      .eq('count_id', countId)
      .order('counted_at')
    if (error) throw error
    return data.map(l => ({
      id: l.id,
      variantId: l.variant_id,
      counted: Number(l.counted),
      expected: Number(l.expected),
      difference: l.difference === null ? undefined : Number(l.difference),
      countedAt: new Date(l.counted_at),
    }))
  },

  async start(notes?: string): Promise<StockCount> {
    const { data, error } = await supabase.rpc('start_stock_count', { p_notes: notes ?? undefined })
    if (error) throw error
    return mapCount(data as unknown as CountRow)
  },

  async record(countId: string, variantId: string, counted: number): Promise<void> {
    const { error } = await supabase.rpc('record_stock_count', {
      p_count_id: countId,
      p_variant_id: variantId,
      p_counted: counted,
    })
    if (error) throw error
  },

  async approve(countId: string): Promise<number> {
    const { data, error } = await supabase.rpc('approve_stock_count', { p_count_id: countId })
    if (error) throw error
    invalidateProducts()
    return Number((data as unknown as { changed_lines: number }).changed_lines)
  },

  async cancel(countId: string): Promise<void> {
    const { error } = await supabase.rpc('cancel_stock_count', { p_count_id: countId })
    if (error) throw error
  },
}

// Cash shifts
export interface CashShift {
  id: string
  sessionNo: string
  status: 'open' | 'closed'
  openingFloat: number
  openedAt: Date
  cashSales: number
  cashRefunds: number
  cashIn: number
  cashOut: number
  expectedCash: number
  otherPayments: Record<string, number>
  countedCash?: number
  variance?: number
  closedAt?: Date
}

type ShiftSummary = {
  session: {
    id: string
    session_no: string
    status: string
    opening_float: number
    opened_at: string
    counted_cash: number | null
    variance: number | null
    closed_at: string | null
  }
  cash_sales: number
  cash_refunds: number
  cash_in: number
  cash_out: number
  expected_cash: number
  other_payments: Record<string, number>
}

function mapShift(s: ShiftSummary | null): CashShift | null {
  if (!s) return null
  return {
    id: s.session.id,
    sessionNo: s.session.session_no,
    status: s.session.status as CashShift['status'],
    openingFloat: Number(s.session.opening_float),
    openedAt: new Date(s.session.opened_at),
    cashSales: Number(s.cash_sales),
    cashRefunds: Number(s.cash_refunds),
    cashIn: Number(s.cash_in),
    cashOut: Number(s.cash_out),
    expectedCash: Number(s.expected_cash),
    otherPayments: Object.fromEntries(Object.entries(s.other_payments || {}).map(([k, v]) => [k, Number(v)])),
    countedCash: s.session.counted_cash === null ? undefined : Number(s.session.counted_cash),
    variance: s.session.variance === null ? undefined : Number(s.session.variance),
    closedAt: s.session.closed_at ? new Date(s.session.closed_at) : undefined,
  }
}

type ShiftHistoryResult = Database['public']['Functions']['list_cash_sessions']['Returns'][number]
// RPC return declarations don't encode SQL nullability for open sessions.
export type ShiftHistoryRow = Omit<ShiftHistoryResult, 'closed_at' | 'counted_cash' | 'variance' | 'closing_notes' | 'closed_by_name'> & {
  closed_at: string | null; counted_cash: number | null; variance: number | null;
  closing_notes: string | null; closed_by_name: string | null
}
export interface ShiftFilters { from?: string; to?: string; user_id?: string; status?: string; only_variance?: boolean }
export interface ShiftDetail {
  summary: Omit<ShiftSummary, 'session'> & {
    session: Database['public']['Tables']['cash_sessions']['Row'];
    user_name: string; closed_by_name: string | null; over_limit: boolean
  }
  movements: (Pick<Database['public']['Tables']['cash_movements']['Row'], 'id' | 'created_at' | 'movement_type' | 'amount' | 'reason'> & {
    user_name: string | null; document_no: string | null
  })[]
}

export const shiftsService = {
  async list(filters: ShiftFilters, page = 0, limit = 50): Promise<ShiftHistoryRow[]> {
    const { data, error } = await supabase.rpc('list_cash_sessions', { p: { ...filters, limit, offset: page * limit } })
    if (error) throw error
    return data
  },
  async detail(id: string): Promise<ShiftDetail> {
    const { data, error } = await supabase.rpc('cash_session_detail', { p_session_id: id })
    if (error) throw error
    return data as unknown as ShiftDetail
  },
  async forceClose(id: string, counted: number, notes: string, requestId: string): Promise<void> {
    const { error } = await supabase.rpc('force_close_cash_session', {
      p_session_id: id, p_counted_cash: counted, p_notes: notes, p_request_id: requestId,
    })
    if (error) throw error
    invalidateTransactions()
  },
  async current(): Promise<CashShift | null> {
    const { data, error } = await supabase.rpc('current_cash_session')
    if (error) throw error
    return mapShift(data as unknown as ShiftSummary | null)
  },

  async open(openingFloat: number): Promise<CashShift> {
    const { data, error } = await supabase.rpc('open_cash_session', { p_opening_float: openingFloat })
    if (error) throw error
    invalidateTransactions()
    return mapShift(data as unknown as ShiftSummary)!
  },

  // Positive: cash put in. Negative: cash taken out.
  async move(amount: number, reason: string): Promise<CashShift> {
    const { data, error } = await supabase.rpc('record_cash_movement', { p_amount: amount, p_reason: reason })
    if (error) throw error
    invalidateTransactions()
    return mapShift(data as unknown as ShiftSummary)!
  },

  async close(countedCash: number, notes?: string): Promise<CashShift> {
    const { data, error } = await supabase.rpc('close_cash_session', { p_counted_cash: countedCash, p_notes: notes })
    if (error) throw error
    invalidateTransactions()
    return mapShift(data as unknown as ShiftSummary)!
  },
}

// Returns and exchanges
export interface ReturnLookupLine {
  saleLineId: string
  variantId: string | null
  description: string
  sku?: string
  unit: string
  quantity: number
  total: number
  returned: number
  isGift: boolean
}

export interface ReturnLookup {
  sale: {
    id: string
    invoiceNumber: string
    createdAt: Date
    customerId?: string
    customerName?: string
    cashier?: string
    total: number
    status: string
  }
  returnWindowDays: number
  withinWindow: boolean
  lines: ReturnLookupLine[]
  previousReturns: { returnNo: string; refundTotal: number; createdAt: Date }[]
}

export interface ReturnLineInput {
  saleLineId: string
  quantity: number
  condition: 'resaleable' | 'damaged' | 'faulty'
}

export type RefundMethod = 'cash' | 'card' | 'digital' | 'credit'

type LookupRow = {
  sale: { id: string; invoice_number: string; created_at: string; customer_id: string | null; customer_name: string | null;
          cashier: string | null; total: number; status: string }
  return_window_days: number
  within_window: boolean
  lines: { sale_line_id: string; variant_id: string | null; description: string; sku: string | null; unit: string;
           quantity: number; total: number; returned: number; is_gift: boolean }[]
  returns: { return_no: string; refund_total: number; created_at: string }[]
}

const toServerLines = (lines: ReturnLineInput[]) =>
  lines.map(l => ({ sale_line_id: l.saleLineId, quantity: l.quantity, condition: l.condition }))

export const returnsService = {
  async lookup(invoiceNumber: string): Promise<ReturnLookup> {
    const { data, error } = await supabase.rpc('find_sale_for_return', { p_invoice: invoiceNumber })
    if (error) throw error
    const r = data as unknown as LookupRow
    return {
      sale: {
        id: r.sale.id,
        invoiceNumber: r.sale.invoice_number,
        createdAt: new Date(r.sale.created_at),
        customerId: r.sale.customer_id ?? undefined,
        customerName: r.sale.customer_name ?? undefined,
        cashier: r.sale.cashier ?? undefined,
        total: Number(r.sale.total),
        status: r.sale.status,
      },
      returnWindowDays: r.return_window_days,
      withinWindow: r.within_window,
      lines: r.lines.map(l => ({
        saleLineId: l.sale_line_id,
        variantId: l.variant_id,
        description: l.description,
        sku: l.sku ?? undefined,
        unit: l.unit,
        quantity: Number(l.quantity),
        total: Number(l.total),
        returned: Number(l.returned),
        isGift: l.is_gift,
      })),
      previousReturns: r.returns.map(x => ({ returnNo: x.return_no, refundTotal: Number(x.refund_total), createdAt: new Date(x.created_at) })),
    }
  },

  async refund(input: { requestId: string; saleId: string; reason: string; method: RefundMethod; lines: ReturnLineInput[] }) {
    const { data, error } = await supabase.rpc('post_return', {
      p: {
        request_id: input.requestId,
        sale_id: input.saleId,
        reason: input.reason,
        refund_method: input.method,
        lines: toServerLines(input.lines),
      } as unknown as Json,
    })
    if (error) throw error
    const r = (data as unknown as { return: { return_no: string; refund_total: number } }).return
    invalidateTransactions()
    return { returnNo: r.return_no, refundTotal: Number(r.refund_total) }
  },

  async exchange(input: {
    requestId: string
    saleId: string
    reason: string
    returnLines: ReturnLineInput[]
    newItems: CartItem[]
    salespersonId?: string
    payments: PaymentInput[]
    refundMethod: RefundMethod
  }) {
    const { data, error } = await supabase.rpc('post_exchange', {
      p: {
        request_id: input.requestId,
        sale_id: input.saleId,
        reason: input.reason,
        return_lines: toServerLines(input.returnLines),
        salesperson_id: input.salespersonId ?? null,
        new_lines: input.newItems.map(item => ({ variant_id: item.product.id, quantity: item.quantity })),
        payments: input.payments.map(p => ({
          method: p.method, amount: p.amount ?? null, tendered: p.tendered ?? null, reference: p.reference ?? null,
          card_type: p.cardType ?? null, card_last4: p.cardLast4 ?? null,
        })),
        refund_method: input.refundMethod,
      } as unknown as Json,
    })
    if (error) throw error
    const r = data as unknown as {
      return: { return_no: string; refund_total: number }
      sale: { invoice_number: string; total: number }
      customer_paid: number
      refunded: number
    }
    invalidateTransactions()
    return {
      returnNo: r.return.return_no,
      credit: Number(r.return.refund_total),
      newInvoice: r.sale.invoice_number,
      newTotal: Number(r.sale.total),
      customerPaid: Number(r.customer_paid),
      refunded: Number(r.refunded),
    }
  },
}

// Customers Service
export interface CustomerPaymentReceipt {
  payment_no: string; paid: number; balance: number
  payments: { method: string; amount: number; reference: string | null }[]
}
export interface CustomerStatementData {
  customer: { id: string; name: string; phone: string | null; credit_limit: number; balance: number }
  opening_balance: number
  closing_balance: number
  entries: { id: number; date: string; type: string; document_no: string | null; note: string | null; debit: number; credit: number; balance: number }[]
}
function mapCustomer(customer: Database['public']['Tables']['customers']['Row']): Customer {
  return {
    emailMarketingConsent: customer.email_marketing_consent ?? null,
    smsMarketingConsent: customer.sms_marketing_consent ?? null,
    emailConsentAt: customer.email_consent_at, smsConsentAt: customer.sms_consent_at,
    id: customer.id, name: customer.name, email: customer.email || '', phone: customer.phone || '',
    address: customer.address || '', creditLimit: customer.credit_limit || 0, creditUsed: customer.credit_used || 0,
    priceTier: customer.price_tier || 'Standard', totalPurchases: customer.total_purchases || 0,
    lastPurchase: customer.last_purchase ? new Date(customer.last_purchase) : undefined,
    createdAt: new Date(customer.created_at ?? Date.now()),
  }
}
export const customersService = {
  async owing(q = '', page = 0, limit = 50) {
    const { data, error } = await supabase.rpc('customers_with_balance', { p: { q: customerSearchTerm(q), limit, offset: page * limit } })
    if (error) throw error
    return data.map(row => ({
      ...mapCustomer(row.customer as unknown as Database['public']['Tables']['customers']['Row']),
      oldestUnpaidDate: row.oldest_unpaid_date as string | null,
      lastPaymentDate: row.last_payment_date as string | null,
      totalCount: row.total_count,
    }))
  },
  async statement(id: string, from: string, to: string): Promise<CustomerStatementData> {
    const { data, error } = await supabase.rpc('customer_statement', { p_customer: id, p_from: from, p_to: to })
    if (error) throw error
    return data as unknown as CustomerStatementData
  },
  async collect(id: string, payments: PaymentInput[], requestId: string, note?: string): Promise<CustomerPaymentReceipt> {
    const { data, error } = await supabase.rpc('post_customer_payment', { p: {
      customer_id: id, request_id: requestId, note: note ?? null,
      payments: payments.map(payment => ({ method: payment.method, amount: payment.amount, tendered: payment.tendered,
        reference: payment.reference, card_last4: payment.cardLast4 })),
    } })
    if (error) throw error
    invalidateTransactions()
    return data as unknown as CustomerPaymentReceipt
  },
  async adjust(id: string, amount: number, reason: string, requestId: string): Promise<void> {
    const { error } = await supabase.rpc('adjust_customer_balance', { p_customer: id, p_amount: amount, p_reason: reason, p_request_id: requestId })
    if (error) throw error
    invalidateTransactions()
  },
  async getById(id: string): Promise<Customer> {
    const { data, error } = await supabase.from('customers').select('*').eq('id', id).single()
    if (error) throw error
    return mapCustomer(data)
  },
  async search(q: string, limit = 20): Promise<Customer[]> {
    if (!q.trim()) return []
    const { data, error } = await supabase.from('customers').select('*')
      .or(customerSearchFilter(q)).order('name').order('id').limit(limit)
    if (error) throw error
    return data.map(mapCustomer)
  },

  // sort: name A-Z, most recently updated, or newest added first
  async list(page: number, pageSize = 50, q = '', sort: 'name' | 'updated' | 'newest' = 'name') {
    let query = supabase.from('customers').select('*', { count: 'exact' })
    if (q.trim()) query = query.or(customerSearchFilter(q))
    if (sort !== 'name') query = query.order(sort === 'updated' ? 'updated_at' : 'created_at', { ascending: false })
    const { data, count, error } = await query.order('name').order('id')
      .range(page * pageSize, (page + 1) * pageSize - 1)
    if (error) throw error
    return { rows: data.map(mapCustomer), total: count ?? 0 }
  },

  async create(customer: Omit<Customer, 'id' | 'createdAt'>): Promise<Customer> {
    const { data, error } = await supabase
      .from('customers')
      .insert({
        name: customer.name,
        email: customer.email.trim() || null,
        phone: customer.phone.trim() || null,
        email_marketing_consent: customer.emailMarketingConsent ?? null,
        sms_marketing_consent: customer.smsMarketingConsent ?? null,
        address: customer.address,
        credit_limit: customer.creditLimit,
        price_tier: customer.priceTier,
        total_purchases: customer.totalPurchases,
        last_purchase: customer.lastPurchase?.toISOString()
      })
      .select()
      .single()

    if (error) throw error
    invalidateTransactions()
    void queryClient.invalidateQueries({ queryKey: ['marketing'] })

    return mapCustomer(data)
  },

  async update(id: string, customer: Partial<Customer>): Promise<Customer> {
    // Only include fields that are actually provided
    const updateData: Database['public']['Tables']['customers']['Update'] = {};
    
    if (customer.name !== undefined) updateData.name = customer.name;
    if (customer.email !== undefined) updateData.email = customer.email.trim() || null;
    if (customer.emailMarketingConsent !== undefined) updateData.email_marketing_consent = customer.emailMarketingConsent;
    if (customer.smsMarketingConsent !== undefined) updateData.sms_marketing_consent = customer.smsMarketingConsent;
    if (customer.phone !== undefined) updateData.phone = customer.phone.trim() || null;
    if (customer.address !== undefined) updateData.address = customer.address;
    if (customer.creditLimit !== undefined) updateData.credit_limit = customer.creditLimit;
    if (customer.priceTier !== undefined) updateData.price_tier = customer.priceTier;
    if (customer.totalPurchases !== undefined) updateData.total_purchases = customer.totalPurchases;
    if (customer.lastPurchase !== undefined) updateData.last_purchase = customer.lastPurchase?.toISOString();

    const { data, error } = await supabase
      .from('customers')
      .update(updateData)
      .eq('id', id)
      .select()
      .single()

    if (error) throw error
    invalidateTransactions()
    void queryClient.invalidateQueries({ queryKey: ['marketing'] })

    return mapCustomer(data)
  },

  async delete(id: string): Promise<void> {
    const { error } = await supabase
      .from('customers')
      .delete()
      .eq('id', id)

    if (error) throw error
    invalidateTransactions()
  }
}

// Sales Service
type SaleRow = Database['public']['Tables']['sales']['Row']

function mapSale(sale: SaleRow): Sale {
  return {
    id: sale.id,
    invoiceNumber: sale.invoice_number,
    customerId: sale.customer_id || undefined,
    customerName: sale.customer_name || undefined,
    items: sale.items as unknown as CartItem[],
    subtotal: sale.subtotal || 0,
    discountAmount: sale.discount_amount || 0,
    taxAmount: sale.tax_amount || 0,
    total: sale.total || 0,
    paymentMethod: sale.payment_method as Sale['paymentMethod'],
    cardDetails: (sale.card_details as unknown as Sale['cardDetails']) || undefined,
    status: sale.status as Sale['status'],
    cashier: sale.cashier || '',
    timestamp: new Date(sale.created_at || Date.now()),
    receiptNumber: sale.receipt_number || sale.invoice_number,
    notes: sale.notes || undefined,
    appliedDiscounts: sale.applied_discounts as unknown as Sale['appliedDiscounts'],
    freeGifts: sale.free_gifts as unknown as Sale['freeGifts']
  }
}

export interface SalesSearchFilters {
  from?: string
  to?: string
  status?: 'completed' | 'credit' | 'draft' | 'returned' | 'refunded'
  method?: 'cash' | 'card' | 'digital' | 'credit' | 'exchange'
  q?: string
}
export type TransactionRow = Database['public']['Functions']['search_sales']['Returns'][number]
type LineRow = Database['public']['Tables']['sale_lines']['Row']
type PaymentRow = Database['public']['Tables']['payments']['Row']
type ReturnRow = Database['public']['Tables']['returns']['Row']
export interface SaleDetail {
  header: Pick<SaleRow, 'id' | 'invoice_number' | 'receipt_number' | 'created_at' | 'status' |
    'customer_id' | 'customer_name' | 'subtotal' | 'discount_amount' | 'tax_amount' | 'total' | 'payment_method' | 'notes'> & { cashier_name: string | null }
  lines: (Pick<LineRow, 'id' | 'line_no' | 'variant_id' | 'description' | 'sku' | 'unit' | 'quantity' | 'unit_price' |
    'gross' | 'manual_discount' | 'promotion_discount' | 'net' | 'taxable' | 'tax' | 'total' | 'is_gift'> & { returned_quantity: number })[]
  payments: Pick<PaymentRow, 'id' | 'created_at' | 'direction' | 'method' | 'amount' | 'tendered' | 'change_given' | 'reference' | 'card_type' | 'card_last4' | 'return_id'>[]
  returns: Pick<ReturnRow, 'id' | 'return_no' | 'created_at' | 'reason' | 'refund_total' | 'refund_method'>[]
}

// Adapt ledger snapshots only for the existing cart and receipt interfaces.
// Neither legacy sales.items nor the startup sales cache is consulted.
export function saleFromDetail(detail: SaleDetail): Sale {
  const h = detail.header
  const timestamp = new Date(h.created_at || Date.now())
  const item = (line: SaleDetail['lines'][number]): CartItem => ({
    product: {
      id: line.variant_id ?? line.id, styleId: '', name: line.description, sku: line.sku ?? '',
      kind: line.unit === 'job' ? 'service' : 'garment',
      price: line.unit_price, unit: line.unit,
      cost: 0, stock: 0, minStock: 0, category: '', description: '',
      taxable: line.taxable, active: true, createdAt: timestamp, updatedAt: timestamp,
    },
    quantity: line.quantity,
    discount: line.manual_discount, discountType: 'fixed', subtotal: line.net,
  })
  return {
    id: h.id, invoiceNumber: h.invoice_number, receiptNumber: h.receipt_number ?? h.invoice_number,
    customerId: h.customer_id ?? undefined, customerName: h.customer_name ?? undefined,
    cashier: h.cashier_name ?? '', timestamp, status: h.status as Sale['status'],
    subtotal: h.subtotal ?? 0, discountAmount: h.discount_amount ?? 0, taxAmount: h.tax_amount ?? 0,
    total: h.total ?? 0, paymentMethod: h.payment_method as Sale['paymentMethod'], notes: h.notes ?? undefined,
    items: detail.lines.filter(line => !line.is_gift).map(item),
    freeGifts: detail.lines.filter(line => line.is_gift).map(item),
    payments: detail.payments.filter(p => p.direction === 'in' && !p.return_id).map(p => ({
      method: p.method, amount: p.amount, tendered: p.tendered ?? undefined, changeGiven: p.change_given,
      reference: p.reference ?? undefined, cardType: p.card_type ?? undefined, cardLast4: p.card_last4 ?? undefined,
    })),
  }
}

export const salesService = {
  async search(filters: SalesSearchFilters, page = 0, pageSize = 50): Promise<TransactionRow[]> {
    const { data, error } = await supabase.rpc('search_sales', {
      p: { ...filters, limit: pageSize, offset: page * pageSize },
    })
    if (error) throw error
    return data
  },

  async detail(id: string): Promise<SaleDetail | null> {
    const { data, error } = await supabase.rpc('sale_detail', { p_sale_id: id })
    if (error) throw error
    return data as unknown as SaleDetail | null
  },
  // Prices a basket on the server (prices, promotions, discount limits, tax). Saves nothing.
  async quote(request: CheckoutRequest): Promise<SaleQuote> {
    const { data, error } = await supabase.rpc('quote_sale', { p_request: toServerRequest(request) })
    if (error) throw error
    return mapQuote(data as unknown as ServerQuote)
  },

  // Posts a sale in one database transaction. Reusing the same requestId for a
  // retry returns the original sale instead of charging twice.
  async post(request: CheckoutRequest & {
    requestId: string
    status?: 'completed' | 'draft'
    notes?: string
  }): Promise<Sale> {
    const { data, error } = await supabase.rpc('post_sale', {
      p_request: {
        ...(toServerRequest(request) as Record<string, Json>),
        request_id: request.requestId,
        status: request.status ?? 'completed',
        notes: request.notes ?? null,
        salesperson_id: request.salespersonId ?? null,
      } as unknown as Json,
    })
    if (error) throw error
    const result = data as unknown as {
      sale: SaleRow
      payments: { method: string; amount: number; tendered: number | null; change_given: number; reference: string | null;
                  card_type: string | null; card_last4: string | null }[]
    }
    invalidateTransactions()
    return {
      ...mapSale(result.sale),
      payments: (result.payments || []).map(p => ({
        method: p.method,
        amount: Number(p.amount),
        tendered: p.tendered === null ? undefined : Number(p.tendered),
        changeGiven: Number(p.change_given),
        reference: p.reference ?? undefined,
        cardType: p.card_type ?? undefined,
        cardLast4: p.card_last4 ?? undefined,
      })),
    }
  },

  async delete(id: string): Promise<void> {
    const { error } = await supabase
      .from('sales')
      .delete()
      .eq('id', id)
      .eq('status', 'draft')

    if (error) throw error
    invalidateTransactions()
  }
}

export interface PaymentInput {
  method: 'cash' | 'card' | 'digital' | 'credit'
  amount?: number
  tendered?: number
  reference?: string
  cardType?: string
  cardLast4?: string
  bankName?: string
  holderName?: string
}

export interface CheckoutRequest {
  salespersonId?: string
  cart: CartItem[]
  customerId?: string
  payments: PaymentInput[]
  discountCode?: string
  /** Automatic promotions the cashier removed from this sale. */
  skippedPromotions?: string[]
}

export interface SaleQuote {
  branchId: string
  subtotal: number
  discountAmount: number
  promotionDiscount: number
  taxAmount: number
  taxRate: number
  total: number
  appliedDiscounts: NonNullable<Sale['appliedDiscounts']>
  gifts: { description: string; quantity: number }[]
}

interface ServerQuote {
  branch_id: string
  subtotal: number
  discount_amount: number
  promotion_discount: number
  tax_amount: number
  tax_rate: number
  total: number
  applied_discounts: NonNullable<Sale['appliedDiscounts']>
  lines: { description: string; quantity: number; is_gift: boolean }[]
}

function toServerRequest(request: CheckoutRequest): Json {
  return {
    customer_id: request.customerId ?? null,
    discount_code: request.discountCode?.trim() || null,
    skipped_promotions: request.skippedPromotions ?? [],
    lines: request.cart.map(item => ({
      variant_id: item.product.id,
      quantity: item.quantity,
      discount_type: 'fixed',
      discount_value: item.discount || 0,
    })),
    payments: request.payments.map(p => ({
      method: p.method,
      amount: p.amount ?? null,
      tendered: p.tendered ?? null,
      reference: p.reference ?? null,
      card_type: p.cardType ?? null,
      card_last4: p.cardLast4 ?? null,
      bank_name: p.bankName ?? null,
      holder_name: p.holderName ?? null,
    })),
  } as unknown as Json
}

function mapQuote(q: ServerQuote): SaleQuote {
  return {
    branchId: q.branch_id,
    subtotal: Number(q.subtotal),
    discountAmount: Number(q.discount_amount),
    promotionDiscount: Number(q.promotion_discount),
    taxAmount: Number(q.tax_amount),
    taxRate: Number(q.tax_rate),
    total: Number(q.total),
    appliedDiscounts: q.applied_discounts || [],
    gifts: (q.lines || []).filter(l => l.is_gift).map(l => ({ description: l.description, quantity: Number(l.quantity) })),
  }
}

// Discounts Service
export const discountsService = {
  async getAll(): Promise<Discount[]> {
    const { data, error } = await supabase
      .from('discounts')
      .select('*')
      .order('name')

    if (error) throw error

    return data.map(discount => ({
      id: discount.id,
      name: discount.name,
      description: discount.description || '',
      type: discount.type as Discount['type'],
      value: discount.value || 0,
      conditions: discount.conditions as unknown as Discount['conditions'],
      freeGiftProducts: discount.free_gift_products || undefined,
      minAmount: discount.min_amount || undefined,
      maxDiscount: discount.max_discount || undefined,
      validFrom: new Date(discount.valid_from ?? Date.now()),
      validTo: new Date(discount.valid_to ?? Date.now()),
      validDays: discount.valid_days || undefined,
      active: discount.active ?? true,
      createdAt: new Date(discount.created_at ?? Date.now())
    }))
  },

  async create(discount: Omit<Discount, 'id' | 'createdAt'>): Promise<Discount> {
    const { data, error } = await supabase
      .from('discounts')
      .insert({
        name: discount.name,
        description: discount.description,
        type: discount.type,
        value: discount.value,
        conditions: discount.conditions as unknown as Json,
        free_gift_products: discount.freeGiftProducts,
        min_amount: discount.minAmount,
        max_discount: discount.maxDiscount,
        valid_from: discount.validFrom.toISOString(),
        valid_to: discount.validTo.toISOString(),
        valid_days: discount.validDays,
        active: discount.active
      })
      .select()
      .single()

    if (error) throw error
    void queryClient.invalidateQueries({ queryKey: queryKeys.discounts })

    return {
      id: data.id,
      name: data.name,
      description: data.description || '',
      type: data.type as Discount['type'],
      value: data.value || 0,
      conditions: data.conditions as unknown as Discount['conditions'],
      freeGiftProducts: data.free_gift_products || undefined,
      minAmount: data.min_amount || undefined,
      maxDiscount: data.max_discount || undefined,
      validFrom: new Date(data.valid_from ?? Date.now()),
      validTo: new Date(data.valid_to ?? Date.now()),
      validDays: data.valid_days || undefined,
      active: data.active ?? true,
      createdAt: new Date(data.created_at ?? Date.now())
    }
  },

  async update(id: string, discount: Partial<Discount>): Promise<Discount> {
    const { data, error } = await supabase
      .from('discounts')
      .update({
        name: discount.name,
        description: discount.description,
        type: discount.type,
        value: discount.value,
        conditions: discount.conditions as unknown as Json,
        free_gift_products: discount.freeGiftProducts,
        min_amount: discount.minAmount,
        max_discount: discount.maxDiscount,
        valid_from: discount.validFrom?.toISOString(),
        valid_to: discount.validTo?.toISOString(),
        valid_days: discount.validDays,
        active: discount.active
      })
      .eq('id', id)
      .select()
      .single()

    if (error) throw error
    void queryClient.invalidateQueries({ queryKey: queryKeys.discounts })

    return {
      id: data.id,
      name: data.name,
      description: data.description || '',
      type: data.type as Discount['type'],
      value: data.value || 0,
      conditions: data.conditions as unknown as Discount['conditions'],
      freeGiftProducts: data.free_gift_products || undefined,
      minAmount: data.min_amount || undefined,
      maxDiscount: data.max_discount || undefined,
      validFrom: new Date(data.valid_from ?? Date.now()),
      validTo: new Date(data.valid_to ?? Date.now()),
      validDays: data.valid_days || undefined,
      active: data.active ?? true,
      createdAt: new Date(data.created_at ?? Date.now())
    }
  },

  async delete(id: string): Promise<void> {
    const { error } = await supabase
      .from('discounts')
      .delete()
      .eq('id', id)

    if (error) throw error
    void queryClient.invalidateQueries({ queryKey: queryKeys.discounts })
  }
}

// Settings Service: map persisted columns once for both loading and saving.
type SettingsRow = Database['public']['Tables']['app_settings']['Row']
function mapSettings(data: SettingsRow): AppSettings {
  return {
    storeName: platformStoreName(data.store_name), storeAddress: data.store_address || '',
    storePhone: data.store_phone || '', storeEmail: platformStoreEmail(data.store_email), storeLogo: data.store_logo || undefined,
    taxRate: data.tax_rate ?? 0, currency: data.currency || 'PKR',
    interfaceMode: (data.interface_mode as AppSettings['interfaceMode']) || 'touch',
    autoBackup: data.auto_backup ?? true, receiptPrinter: data.receipt_printer ?? true,
    theme: (data.theme as AppSettings['theme']) || 'light', invoicePrefix: data.invoice_prefix || 'INV', invoiceCounter: data.invoice_counter ?? 1000,
    cashVarianceAlert: data.cash_variance_alert, maxCashierDiscountPercent: data.max_cashier_discount_percent,
    returnWindowDays: data.return_window_days,
    deliveryFee: data.delivery_fee, freeDeliveryOver: data.free_delivery_over, codEnabled: data.cod_enabled, codMaxTotal: data.cod_max_total,
    onlineCardEnabled: data.online_card_enabled, onlineMaxPendingOrders: data.online_max_pending_orders, onlineMaxOpenCodOrders: data.online_max_open_cod_orders,
    receiptHeader: platformReceiptText(data.receipt_header), receiptFooter: platformReceiptText(data.receipt_footer), ntn: data.ntn ?? '', strn: data.strn ?? '',
  }
}
const settingsColumns = {
  deliveryFee: 'delivery_fee', freeDeliveryOver: 'free_delivery_over', codEnabled: 'cod_enabled', codMaxTotal: 'cod_max_total',
  onlineCardEnabled: 'online_card_enabled', onlineMaxPendingOrders: 'online_max_pending_orders', onlineMaxOpenCodOrders: 'online_max_open_cod_orders',
  storeName: 'store_name', storeAddress: 'store_address', storePhone: 'store_phone', storeEmail: 'store_email', storeLogo: 'store_logo',
  taxRate: 'tax_rate', currency: 'currency', interfaceMode: 'interface_mode', autoBackup: 'auto_backup', receiptPrinter: 'receipt_printer',
  theme: 'theme', invoicePrefix: 'invoice_prefix', invoiceCounter: 'invoice_counter', cashVarianceAlert: 'cash_variance_alert',
  maxCashierDiscountPercent: 'max_cashier_discount_percent', returnWindowDays: 'return_window_days',
  receiptHeader: 'receipt_header', receiptFooter: 'receipt_footer', ntn: 'ntn', strn: 'strn',
} as const satisfies Record<keyof AppSettings, keyof SettingsRow>

export const settingsService = {
  async ping(signal: AbortSignal): Promise<void> {
    const { error } = await supabase.from('app_settings').select('id').limit(1).abortSignal(signal)
    if (error) throw error
  },
  async get(): Promise<AppSettings> {
    const { data, error } = await supabase.from('app_settings').select('*').order('created_at').order('id').limit(1).single()
    if (error) throw error
    return mapSettings(data)
  },
  async update(settings: Partial<AppSettings>, requestId: string = crypto.randomUUID()): Promise<AppSettings> {
    const patch: Record<string, Json> = { request_id: requestId }
    for (const key of Object.keys(settings) as (keyof AppSettings)[]) patch[settingsColumns[key]] = settings[key] ?? null
    const { data, error } = await supabase.rpc('update_settings', { p: patch })
    if (error) throw error
    invalidateShifts()
    return mapSettings(data as unknown as SettingsRow)
  },
}

// Users Service
type UserRow = Database['public']['Tables']['users']['Row']

function mapUser(user: UserRow): User {
  return {
    id: user.id,
    username: user.username,
    name: user.name,
    email: user.email,
    role: user.role as User['role'],
    permissions: user.permissions || [],
    active: user.active ?? true,
    lastLogin: user.last_login ? new Date(user.last_login) : undefined,
    avatar: user.avatar || undefined
  }
}

async function functionErrorMessage(error: unknown): Promise<string> {
  if (error instanceof FunctionsHttpError) {
    try {
      const body = await error.context.json()
      if (body?.error) return body.error
    } catch {
      // fall through to the generic message
    }
  }
  return error instanceof Error ? error.message : 'Request failed'
}

export const usersService = {
  async getAll(): Promise<User[]> {
    const { data, error } = await supabase
      .from('users')
      .select('*')
      .order('name')

    if (error) throw error

    return data.map(mapUser)
  },

  // Staff accounts are created by the admin-users edge function, which holds the
  // service role key server side and checks that the caller is an administrator.
  async create(user: Omit<User, 'id' | 'permissions' | 'lastLogin'> & { password: string }): Promise<User> {
    const { data, error } = await supabase.functions.invoke('admin-users', {
      body: { action: 'create', ...user }
    })

    if (error) throw new Error(await functionErrorMessage(error))
    void queryClient.invalidateQueries({ queryKey: queryKeys.users })

    return mapUser(data.user)
  },

  async update(id: string, user: Partial<User>): Promise<User> {
    const { data, error } = await supabase
      .from('users')
      .update({
        username: user.username,
        name: user.name,
        email: user.email,
        role: user.role,
        permissions: user.permissions,
        active: user.active,
        avatar: user.avatar,
        last_login: user.lastLogin?.toISOString()
      })
      .eq('id', id)
      .select()
      .single()

    if (error) throw error

    void queryClient.invalidateQueries({ queryKey: queryKeys.users })
    return mapUser(data)
  },

  async delete(id: string): Promise<void> {
    const { error } = await supabase.functions.invoke('admin-users', {
      body: { action: 'delete', userId: id }
    })

    if (error) throw new Error(await functionErrorMessage(error))
    void queryClient.invalidateQueries({ queryKey: queryKeys.users })
  }
}

// Sales Tabs Service
export const salesTabsService = {
  async getByUserId(userId: string): Promise<SalesTab[]> {
    const { data, error } = await supabase
      .from('sales_tabs')
      .select(`
        *,
        selected_customer:customers(*)
      `)
      .eq('user_id', userId)
      .order('created_at')

    if (error) throw error

    return data.map(tab => ({
      id: tab.id,
      name: tab.name,
      cart: (tab.cart as unknown as CartItem[]) || [],
      selectedCustomer: tab.selected_customer ? {
        id: tab.selected_customer.id,
        name: tab.selected_customer.name,
        email: tab.selected_customer.email || '',
        phone: tab.selected_customer.phone || '',
        address: tab.selected_customer.address || '',
        creditLimit: tab.selected_customer.credit_limit || 0,
        creditUsed: tab.selected_customer.credit_used || 0,
        priceTier: tab.selected_customer.price_tier || 'Standard',
        totalPurchases: tab.selected_customer.total_purchases || 0,
        lastPurchase: tab.selected_customer.last_purchase ? new Date(tab.selected_customer.last_purchase ?? Date.now()) : undefined,
        createdAt: new Date(tab.selected_customer.created_at ?? Date.now())
      } : null,
      createdAt: new Date(tab.created_at ?? Date.now())
    }))
  },

  async create(userId: string, tab: Omit<SalesTab, 'id' | 'createdAt'>): Promise<SalesTab> {
    const { data, error } = await supabase
      .from('sales_tabs')
      .insert({
        user_id: userId,
        name: tab.name,
        cart: tab.cart as unknown as Json,
        selected_customer_id: tab.selectedCustomer?.id
      })
      .select()
      .single()

    if (error) throw error

    return {
      id: data.id,
      name: data.name,
      cart: (data.cart as unknown as CartItem[]) || [],
      selectedCustomer: tab.selectedCustomer,
      createdAt: new Date(data.created_at ?? Date.now())
    }
  },

  async update(id: string, tab: Partial<SalesTab>): Promise<SalesTab> {
    const { data, error } = await supabase
      .from('sales_tabs')
      .update({
        name: tab.name,
        cart: tab.cart as unknown as Json,
        selected_customer_id: tab.selectedCustomer?.id
      })
      .eq('id', id)
      .select()
      .single()

    if (error) throw error

    return {
      id: data.id,
      name: data.name,
      cart: (data.cart as unknown as CartItem[]) || [],
      selectedCustomer: tab.selectedCustomer || null,
      createdAt: new Date(data.created_at ?? Date.now())
    }
  },

  async delete(id: string): Promise<void> {
    const { error } = await supabase
      .from('sales_tabs')
      .delete()
      .eq('id', id)

    if (error) throw error
  }
}

export type OpeningBalanceResult = {
  created_customers: number; balances: number; total_amount: number;
  skipped: { row: number; phone: string; reason: string }[];
}
export const goLiveService = {
  async balances(rows: OpeningBalance[], requestId: string): Promise<OpeningBalanceResult> {
    const { data, error } = await supabase.rpc('import_opening_balances', { p: { request_id: requestId, rows } })
    if (error) throw error
    invalidateTransactions()
    return data as unknown as OpeningBalanceResult
  },
}

export type ProductImage = Pick<Database['public']['Tables']['product_images']['Row'], 'storage_path' | 'alt' | 'variant_color' | 'sort_order'>
export type WebDetails = { product_guide?: ProductGuide; try_on?: TryOn; slug?: string | null; web_title?: string | null; web_description?: string | null; variants?: { variant_id: string; published: boolean }[] }
export type WebCollection = Database['public']['Tables']['collections']['Row']
function invalidateWebCatalog() {
  invalidateProducts()
  void queryClient.invalidateQueries({ queryKey: queryKeys.webCatalog })
}
async function uploadWebImage(folder: string, blob: Blob) {
  if (!['image/webp', 'image/jpeg'].includes(blob.type)) throw new Error('Prepare a WebP or JPEG image first')
  if (blob.size > 5 * 1024 * 1024) throw new Error('The resized image is over 5 MB. Choose a smaller image')
  const path = folder + '/' + crypto.randomUUID() + (blob.type === 'image/webp' ? '.webp' : '.jpg')
  const { error } = await supabase.storage.from('product-images').upload(path, blob, { contentType: blob.type, upsert: false })
  if (error) throw error
  return path
}
// Staff profile pictures share the public product-images bucket (admins and
// managers may write there) and are saved on the user as an https URL.
export async function uploadAvatar(blob: Blob): Promise<string> {
  const path = await uploadWebImage('avatars', blob)
  return supabase.storage.from('product-images').getPublicUrl(path).data.publicUrl
}
export const webCatalogService = {
  async details(styleId: string) {
    const { data, error } = await supabase.from('product_styles').select('id,name,kind,unit,slug,category:categories(name),web_title,web_description,product_guide,try_on,published,active,track_inventory,variants:product_variants(id,sku,size,color,price,published,active,min_stock,stock:stock_balances(on_hand,reserved,location:locations(active,kind)))').eq('id', styleId).single()
    if (error) throw error
    return data
  },
  async saveWebDetails(styleId: string, details: WebDetails, requestId: string) {
    const { data, error } = await supabase.rpc('save_style_web_details', { p_style: styleId, p: details, p_request_id: requestId })
    if (error) throw error
    invalidateWebCatalog()
    return data
  },
  uploadImage: (styleId: string, blob: Blob) => uploadWebImage('styles/' + styleId, blob),
  uploadSpinFrame: (styleId: string, blob: Blob) => uploadWebImage('styles/' + styleId + '/spin', blob),
  // 3D try-on models have their own bucket, as they are larger than photos.
  async uploadTryOnModel(styleId: string, file: File) {
    if (!file.name.toLowerCase().endsWith('.glb')) throw new Error('Choose a .glb 3D model file')
    if (file.size > tryOnLimits.modelBytes) throw new Error('Choose a 3D model of 25 MB or less')
    const path = 'styles/' + styleId + '/' + crypto.randomUUID() + '.glb'
    const { error } = await supabase.storage.from('try-on-models').upload(path, file, { contentType: 'model/gltf-binary', upsert: false })
    if (error) throw error
    return path
  },
  async deleteTryOnModel(path: string) {
    const { error } = await supabase.storage.from('try-on-models').remove([path])
    if (error) throw error
  },
  publicUrl: (path: string) => supabase.storage.from('product-images').getPublicUrl(path).data.publicUrl,
  async listImages(styleId: string): Promise<ProductImage[]> {
    const { data, error } = await supabase.from('product_images').select('storage_path,alt,variant_color,sort_order').eq('style_id', styleId).order('sort_order').order('id')
    if (error) throw error
    return data
  },
  // First photo per style (and per style+colour) for list thumbnails: the
  // style editor saves photos to product_images, not the legacy image_url.
  async coverImages(styleIds: string[]): Promise<Map<string, string>> {
    const { data, error } = await supabase.from('product_images').select('style_id,storage_path,variant_color').in('style_id', styleIds).order('sort_order').order('id')
    if (error) throw error
    const covers = new Map<string, string>()
    for (const row of data) {
      const url = webCatalogService.publicUrl(row.storage_path)
      if (!covers.has(row.style_id)) covers.set(row.style_id, url)
      const colourKey = row.style_id + '|' + (row.variant_color ?? '').toLowerCase()
      if (row.variant_color && !covers.has(colourKey)) covers.set(colourKey, url)
    }
    return covers
  },
  async saveImages(styleId: string, images: ProductImage[], requestId: string) {
    const { data, error } = await supabase.rpc('save_product_images', { p_style: styleId, p_images: images, p_request_id: requestId })
    if (error) throw error
    invalidateWebCatalog()
    return data
  },
  async deleteObject(path: string) {
    const { error } = await supabase.storage.from('product-images').remove([path])
    if (error) throw error
    invalidateWebCatalog()
  },
  async publish(styleId: string, on: boolean, dryRun: boolean): Promise<string[]> {
    const { data, error } = await supabase.rpc('publish_style', { p_style: styleId, p_published: on, p_dry_run: dryRun })
    if (error) throw error
    if (!dryRun) invalidateWebCatalog()
    return dryRun && Array.isArray(data) ? data.filter((v): v is string => typeof v === 'string') : []
  },
  async preview(slug: string) {
    const { data, error } = await supabase.rpc('catalog_product', { p_slug: slug })
    if (error) throw error
    return data
  },
  async flags(ids: string[]) {
    if (!ids.length) return []
    const { data, error } = await supabase.from('product_styles').select('id,published').in('id', ids)
    if (error) throw error
    return data
  },
  async inventory(params: { q: string; category?: string; categories?: string[]; published: boolean; page: number; sort?: ProductSort }) {
    const location = await getSellingLocationId()
    let query = supabase.from('product_variants').select('*,style:product_styles!inner(id,name,kind,unit,taxable,track_inventory,active,description,image_url,published,category:categories(name)),barcodes(code),stock:stock_balances(location_id,on_hand,reserved)', { count: 'exact' }).eq('active', true).eq('style.active', true).eq('style.published', params.published)
    const q = params.q.trim().replace(/[\\%_]/g, char => '\\' + char)
    if (q) query = query.ilike('style.name', '%' + q + '%')
    const names = params.category ? [params.category] : params.categories
    if (names) {
      const categories = await supabase.from('categories').select('id').in('name', names)
      if (categories.error) throw categories.error
      if (!categories.data.length) return { rows: [], total: 0 }
      query = query.in('style.category_id', categories.data.map(row => row.id))
    }
    if (params.sort === 'updated' || params.sort === 'newest') query = query.order(params.sort === 'updated' ? 'updated_at' : 'created_at', { ascending: false })
    const { data, error, count } = await query.order('sku').order('id').range(params.page * 50, params.page * 50 + 49)
    if (error) throw error
    const costs = await loadCosts(data.map(row => row.id))
    return { rows: data.map(row => mapVariant(row as unknown as VariantRow, costs, location)), total: count ?? 0 }
  },
  collections: {
    async list(): Promise<WebCollection[]> {
      const rows: WebCollection[] = []
      for (let offset = 0; ; offset += 1000) {
        const { data, error } = await supabase.from('collections').select('*').order('sort_order').order('id').range(offset, offset + 999)
        if (error) throw error
        rows.push(...data)
        if (data.length < 1000) return rows
      }
    },
    async save(value: Omit<WebCollection, 'id'> & { id?: string }, requestId: string): Promise<WebCollection> {
      const { data, error } = await supabase.rpc('save_collection', { p: { ...value, request_id: requestId } })
      if (error) throw error
      invalidateWebCatalog()
      return data as unknown as WebCollection
    },
    async setStyles(id: string, ids: string[], requestId: string) {
      const { error } = await supabase.rpc('set_collection_styles', { p_collection: id, p_style_ids: ids, p_request_id: requestId })
      if (error) throw error
      invalidateWebCatalog()
    },
    async listStyles(id: string) {
      const rows: { style_id: string; sort_order: number; style: { id: string; name: string } | null }[] = []
      for (let offset = 0; ; offset += 1000) {
        const { data, error } = await supabase.from('collection_styles').select('style_id,sort_order,style:product_styles(id,name)').eq('collection_id', id).order('sort_order').order('style_id').range(offset, offset + 999)
        if (error) throw error
        rows.push(...data)
        if (data.length < 1000) return rows
      }
    },
    uploadHero: (id: string, blob: Blob) => uploadWebImage('collections/' + id, blob),
  },
}
