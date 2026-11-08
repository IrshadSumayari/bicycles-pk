export type PayMethod = "card" | "wallet";
export type PaymentStatus = "paid" | "failed" | "refunded";
export type ProviderName = "mock" | "easypaisa";

export interface CheckoutOrder {
  orderNo: string;
  amount: number;
  currency: "PKR";
  method: PayMethod;
  phone: string;
  email?: string;
  returnUrl: string;
  expiresAt: string;
}
export interface Checkout {
  redirectUrl: string;
  formFields?: Record<string, string>;
  providerRef: string;
}
export interface PaymentEvent {
  providerRef: string;
  orderNo: string;
  amount: number;
  method: PayMethod;
  status: PaymentStatus;
  raw: unknown;
}
export interface ConfirmationRequest {
  url: URL;
  headers: Headers;
  rawBody: string;
  // Only a trusted staff reconciliation call supplies this context. It must never
  // be populated from an unauthenticated notification body.
  inquiry?: { orderNo: string; providerRef: string };
}
export interface PaymentProvider {
  name: ProviderName;
  createCheckout(order: CheckoutOrder): Promise<Checkout>;
  confirm(
    request: ConfirmationRequest,
  ): Promise<{ valid: boolean; event?: PaymentEvent }>;
}

export class PaymentError extends Error {
  constructor(
    public readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = "PaymentError";
  }
}
