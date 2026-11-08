import { QueryClient } from '@tanstack/react-query';

// Server data (products, customers, sales, ...) is cached and refreshed through
// TanStack Query. React context keeps only UI state such as the cart.
export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 30_000,
      refetchOnWindowFocus: true,
      retry: 1,
      networkMode: 'online',
    },
    mutations: {
      // Posting sales, payments and stock changes must never be retried blindly;
      // retries go through idempotency keys on the server instead.
      retry: false,
    },
  },
});

// Query keys in one place so invalidation after a posting is consistent.
export const queryKeys = {
  onlineOrders: ['onlineOrders'] as const,
  onlineOrderList: (user: string, filters: object) => ['onlineOrders', user, 'list', filters] as const,
  onlineOrder: (user: string, id: string) => ['onlineOrders', user, 'detail', id] as const,
  onlineLocations: ['onlineLocations'] as const,
  webCatalog: ['webCatalog'] as const,
  webDetails: (id: string) => ['webCatalog', 'details', id] as const,
  webImages: (id: string) => ['webCatalog', 'images', id] as const,
  webPreview: (slug: string) => ['webCatalog', 'preview', slug] as const,
  collections: ['webCatalog', 'collections'] as const,
  collectionStyles: (id: string) => ['webCatalog', 'collectionStyles', id] as const,
  webFlags: (ids: string[]) => ['webCatalog', 'flags', ids] as const,
  webCovers: (ids: string[]) => ['webCatalog', 'covers', ids] as const,
  webInventory: (params: object) => ['products', 'webInventory', params] as const,
  quote: (
    cart: readonly unknown[],
    customerId: string | undefined,
    payments: readonly unknown[],
    discountCode?: string,
    skippedPromotions: readonly string[] = [],
  ) => ['quote', cart, customerId, payments, discountCode ?? '', skippedPromotions] as const,
  exchangeQuote: (cart: readonly unknown[], customerId: string | undefined) =>
    ['exchangeQuote', cart, customerId] as const,
  suppliers: ['suppliers'] as const,
  goodsReceipts: ['goodsReceipts'] as const,
  stockCounts: ['stockCounts'] as const,
  stockCountLines: (id?: string) => ['stockCountLines', id] as const,
  sizeSchemes: ['sizeSchemes'] as const,
  allReports: ['reports'] as const,
  productSearch: (userId: string, params: object) => ['products', 'search', userId, params] as const,
  infiniteProducts: (userId: string, params: object) => ['products', 'infinite', userId, params] as const,
  productIds: (userId: string, ids: string[]) => ['products', 'ids', userId, ids] as const,
  productCategories: ['products', 'categories'] as const,
  products: ['products'] as const,
  customerSearch: (userId: string, q: string) =>
    ['customers', 'search', userId, q] as const,
  customers: ['customers'] as const,
  customerList: (userId: string, filters: object, page: number) =>
    ['customers', 'list', userId, filters, page] as const,
  customerAccount: (userId: string, id: string) =>
    ['customers', 'account', userId, id] as const,
  customerStatement: (userId: string, id: string, from: string, to: string) =>
    ['customers', 'statement', userId, id, from, to] as const,
  sales: ['sales'] as const,
  discountList: (userId: string) => ['discounts', 'list', userId] as const,
  discounts: ['discounts'] as const,
  discountCodes: ['discountCodes'] as const,
  discountCodeSettings: ['discountCodes', 'settings'] as const,
  customerDiscountCodes: (customerId: string) => ['discountCodes', 'customer', customerId] as const,
  settings: ['settings'] as const,
  userList: (userId: string) => ['users', 'list', userId] as const,
  users: ['users'] as const,
  salesTabs: (userId: string) => ['salesTabs', userId] as const,
  cashShift: ['cashShift'] as const,
  shiftHistory: ['shiftHistory'] as const,
  shiftList: (userId: string, filters: object, page: number) =>
    ['shiftHistory', 'list', userId, filters, page] as const,
  shiftDetail: (userId: string, id: string) =>
    ['shiftHistory', 'detail', userId, id] as const,
  transactions: ['transactions'] as const,
  transactionList: (userId: string, filters: object, page: number) =>
    ['transactions', 'list', userId, filters, page] as const,
  transactionDetail: (userId: string, id: string) =>
    ['transactions', 'detail', userId, id] as const,
  reports: (
    tab: string,
    from: string,
    to: string,
    extra: Record<string, string | number | undefined> = {},
  ) => ['reports', tab, from, to, extra] as const,
};

export function invalidateProducts() {
  void queryClient.invalidateQueries({ queryKey: queryKeys.products });
}

export function invalidateTransactions() {
  void queryClient.invalidateQueries({ queryKey: ['commissions'] });
  invalidateProducts();
  void queryClient.invalidateQueries({ queryKey: queryKeys.customers });
  invalidateShifts();
  void queryClient.invalidateQueries({ queryKey: queryKeys.transactions });
  void queryClient.invalidateQueries({ queryKey: queryKeys.allReports });
}

export function invalidateShifts() {
  void queryClient.invalidateQueries({ queryKey: queryKeys.shiftHistory });
  void queryClient.invalidateQueries({ queryKey: queryKeys.cashShift });
}
