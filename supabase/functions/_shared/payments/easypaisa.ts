import {
  PaymentError,
  type CheckoutOrder,
  type ConfirmationRequest,
  type PaymentProvider,
} from "./types.ts";

// Deliberately unavailable until the owner's official merchant guide is supplied.
// Hosted-card and wallet contracts differ between guide versions. Do not guess
// endpoint paths, encryption, status codes, IPN acknowledgement or inquiry fields.
export class EasypaisaProvider implements PaymentProvider {
  readonly name = "easypaisa" as const;
  async createCheckout(_order: CheckoutOrder): Promise<never> {
    throw new PaymentError(
      503,
      "Easypaisa integration is awaiting the official merchant guide",
    );
  }
  async confirm(_request: ConfirmationRequest): Promise<never> {
    throw new PaymentError(
      503,
      "Easypaisa integration is awaiting the official merchant guide",
    );
  }
}
