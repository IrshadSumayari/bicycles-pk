export type ProductKind = 'item' | 'pack' | 'service';

// A sellable item: one variant (size / color / fit) of a product style.
export interface Product {
  id: string; // variant id
  styleId: string;
  kind: ProductKind;
  name: string; // style name
  size?: string;
  color?: string;
  fit?: string;
  sku: string;
  barcode?: string; // item barcode
  barcodes?: string[]; // item barcodes, for scanning
  price: number; // per piece or set
  cost: number; // 0 when the user may not see costs
  stock: number; // available on the shop floor (on hand - reserved)
  minStock: number;
  category: string;
  description: string;
  image?: string;
  taxable: boolean;
  active: boolean;
  createdAt: Date;
  updatedAt: Date;
  unit?: string;
  trackInventory?: boolean;
}

// Name with size / color / fit, e.g. "City Bike M Black"
export function productLabel(product: Pick<Product, 'name' | 'size' | 'color' | 'fit'>): string {
  return [product.name, product.size, product.color, product.fit].filter(Boolean).join(' ');
}

export interface Customer {
  emailMarketingConsent?: boolean | null;
  smsMarketingConsent?: boolean | null;
  emailConsentAt?: string | null;
  smsConsentAt?: string | null;
  id: string;
  name: string;
  email: string;
  phone: string;
  address: string;
  creditLimit: number;
  creditUsed: number;
  priceTier: string;
  totalPurchases: number;
  lastPurchase?: Date;
  createdAt: Date;
}

export interface Supplier {
  id: string;
  name: string;
  email: string;
  phone: string;
  address: string;
  paymentTerms: string;
  rating: number;
  createdAt: Date;
}

export interface CartItem {
  product: Product;
  quantity: number;
  discount: number;
  discountType: 'percentage' | 'fixed';
  subtotal: number;
  batchId?: string; // For batch tracking
}

export interface Discount {
  id: string;
  name: string;
  description: string;
  type: 'percentage' | 'fixed' | 'bogo' | 'free_gift';
  value: number;
  conditions: DiscountCondition[];
  freeGiftProducts?: string[]; // Product IDs for free gifts
  minAmount?: number;
  maxDiscount?: number;
  validFrom: Date;
  validTo: Date;
  validDays?: number[]; // 0-6 (Sunday-Saturday)
  active: boolean;
  createdAt: Date;
}

export interface DiscountCondition {
  type: 'min_amount' | 'specific_products' | 'payment_method' | 'customer_tier' | 'card_type' | 'bank_name';
  value: number | string | string[];
  operator?: 'equals' | 'greater_than' | 'less_than' | 'in_array';
  minQuantity?: number; // For specific_products condition - minimum quantity required
}

export interface CardDetails {
  id: string;
  bankName: string;
  cardType: 'visa' | 'mastercard' | 'amex' | 'discover' | 'unionpay' | 'other' | 'unknown';
  // Only the last 4 digits are kept. Full card numbers must never be entered or stored (PCI DSS).
  lastFourDigits: string;
  holderName: string;
}

export interface SalePayment {
  method: string;
  amount: number;
  tendered?: number;
  changeGiven: number;
  reference?: string;
  cardType?: string;
  cardLast4?: string;
}

export interface Sale {
  id: string;
  // Present right after checkout (for the receipt); not loaded in lists
  payments?: SalePayment[];
  invoiceNumber: string;
  customerId?: string;
  customerName?: string;
  items: CartItem[];
  subtotal: number;
  discountAmount: number;
  taxAmount: number;
  total: number;
  paymentMethod: 'cash' | 'card' | 'digital' | 'credit';
  cardDetails?: CardDetails;
  status: 'pending' | 'completed' | 'refunded' | 'credit' | 'draft';
  cashier: string;
  timestamp: Date;
  receiptNumber: string;
  notes?: string;
  appliedDiscounts?: AppliedDiscount[];
  freeGifts?: CartItem[];
}

export interface AppliedDiscount {
  discountId: string;
  discountName: string;
  discountAmount: number;
  type: 'percentage' | 'fixed' | 'bogo' | 'free_gift' | 'code';
  code?: string;
}

export interface SalesTab {
  id: string;
  name: string;
  cart: CartItem[];
  selectedCustomer: Customer | null;
  createdAt: Date;
}

export interface User {
  id: string;
  username: string;
  name: string;
  email: string;
  role: 'admin' | 'manager' | 'cashier';
  permissions: string[];
  active: boolean;
  lastLogin?: Date;
  avatar?: string;
}

export interface AppSettings {
  deliveryFee?: number;
  freeDeliveryOver?: number | null;
  bulkyDeliveryFee?: number;
  assemblyFee?: number | null;
  codEnabled?: boolean;
  codMaxTotal?: number | null;
  onlineCardEnabled?: boolean;
  onlineMaxPendingOrders?: number;
  onlineMaxOpenCodOrders?: number;
  maxCashierDiscountPercent?: number;
  returnWindowDays?: number;
  receiptHeader?: string;
  receiptFooter?: string;
  ntn?: string;
  strn?: string;
  cashVarianceAlert?: number;
  storeName: string;
  storeAddress: string;
  storePhone: string;
  storeEmail: string;
  storeLogo?: string;
  taxRate: number;
  currency: string;
  interfaceMode: 'touch' | 'traditional';
  autoBackup: boolean;
  receiptPrinter: boolean;
  theme: 'light' | 'dark' | 'auto';
  invoicePrefix: string;
  invoiceCounter: number;
}

export interface LoginCredentials {
  username: string;
  password: string;
}
