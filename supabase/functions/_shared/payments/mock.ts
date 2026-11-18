import { parseMockEvent, verifyBody } from "./helpers.ts";
import {
  PaymentError,
  type CheckoutOrder,
  type ConfirmationRequest,
  type PaymentProvider,
} from "./types.ts";

export class MockProvider implements PaymentProvider {
  readonly name = "mock" as const;
  constructor(private readonly secret: string) {
    if (secret.length < 32)
      throw new PaymentError(503, "Mock payment configuration is incomplete");
  }
  async createCheckout(order: CheckoutOrder) {
    // A local test checkout has no real card-entry page and no financial effect.
    // Only a separately signed test notification can change the payment state.
    return {
      redirectUrl: order.returnUrl,
      providerRef: `mock:${order.orderNo}`,
    };
  }
  async confirm(request: ConfirmationRequest) {
    if (request.inquiry) {
      // Mock has no upstream ledger to inquire. Reconciliation must never infer
      // success from an initiated row, a return URL or a staff button.
      throw new PaymentError(
        409,
        "Mock payments need a signed test notification; there is no provider inquiry API",
      );
    }
    if (
      !(await verifyBody(
        this.secret,
        request.rawBody,
        request.headers.get("x-payment-signature"),
      ))
    )
      return { valid: false };
    try {
      return {
        valid: true,
        event: parseMockEvent(JSON.parse(request.rawBody)),
      };
    } catch {
      return { valid: false };
    }
  }
}
