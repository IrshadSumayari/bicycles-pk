import { object, paisa, text } from "./helpers.ts";
import {
  PaymentError,
  type PaymentEvent,
  type PaymentProvider,
  type PayMethod,
} from "./types.ts";

export interface CustomerOrder {
  cardEnabled: boolean;
  accountId: string;
  orderNo: string;
  amount: number;
  paymentMethod: string;
  status: string;
  expiresAt: string | null;
  phone: string;
  email?: string;
}
export interface PaymentBackend {
  customerOrder(request: Request, orderNo: string): Promise<CustomerOrder>;
  initiate(
    order: CustomerOrder,
    provider: string,
    providerRef: string,
    method: PayMethod,
  ): Promise<void>;
  staffPayment(
    request: Request,
    orderNo: string,
  ): Promise<{ orderNo: string; providerRef: string; provider: string }>;
  apply(
    provider: string,
    event: PaymentEvent,
  ): Promise<{ status: string; needs_refund: boolean }>;
}
export interface PaymentDependencies {
  provider(): PaymentProvider;
  backend: PaymentBackend;
  siteUrl: string;
}

async function rawBody(request: Request): Promise<string> {
  const reader = request.body?.getReader();
  if (!reader) throw new PaymentError(400, "Send a request body");
  const decoder = new TextDecoder();
  let size = 0,
    result = "";
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.length;
    if (size > 16_384) {
      await reader.cancel();
      throw new PaymentError(413, "Payment request is too large");
    }
    result += decoder.decode(value, { stream: true });
  }
  return result + decoder.decode();
}
function bodyObject(raw: string): Record<string, unknown> {
  try {
    return object(JSON.parse(raw));
  } catch {
    throw new PaymentError(400, "Send a JSON object");
  }
}
function siteOrigin(siteUrl: string): string {
  let url: URL;
  try {
    url = new URL(siteUrl);
  } catch {
    throw new PaymentError(503, "Website address is not configured");
  }
  if (
    url.username ||
    url.password ||
    (url.protocol !== "https:" &&
      !(
        url.protocol === "http:" &&
        ["localhost", "127.0.0.1"].includes(url.hostname)
      ))
  ) {
    throw new PaymentError(503, "Website address is not configured");
  }
  return url.origin;
}

export function paymentHandler(
  kind: "create" | "webhook" | "check",
  dependencies: PaymentDependencies,
) {
  return async (request: Request): Promise<Response> => {
    let cors: Record<string, string> = {};
    const json = (body: unknown, status = 200) =>
      new Response(JSON.stringify(body), {
        status,
        headers: {
          ...cors,
          "Content-Type": "application/json",
          "Cache-Control": "no-store",
        },
      });
    try {
      const origin = siteOrigin(dependencies.siteUrl);
      if (kind !== "webhook") {
        if (
          kind === "create" &&
          request.headers.has("origin") &&
          request.headers.get("origin") !== origin
        )
          throw new PaymentError(403, "This website cannot start a payment");
        cors = {
          // The POS is hosted separately. Staff checks use an explicit Bearer
          // token, never cookies, and still enforce Auth + role + branch checks.
          "Access-Control-Allow-Origin": kind === "check" ? "*" : origin,
          "Access-Control-Allow-Headers":
            "authorization, apikey, content-type, x-client-info",
          "Access-Control-Allow-Methods": "POST, OPTIONS",
          Vary: "Origin",
        };
        if (request.method === "OPTIONS")
          return new Response(null, { status: 204, headers: cors });
      }
      if (request.method !== "POST")
        return json({ error: "Use POST for payment requests" }, 405);
      const raw = await rawBody(request);
      if (kind === "webhook") {
        const provider = dependencies.provider();
        const confirmation = await provider.confirm({
          url: new URL(request.url),
          headers: request.headers,
          rawBody: raw,
        });
        if (!confirmation.valid || !confirmation.event)
          throw new PaymentError(
            401,
            "Payment notification could not be verified",
          );
        const result = await dependencies.backend.apply(
          provider.name,
          confirmation.event,
        );
        return json({ received: true, ...result });
      }
      const body = bodyObject(raw);
      const orderNo = text(body.orderNo, 50);
      if (!/^WEB-\d{6,}$/.test(orderNo))
        throw new PaymentError(400, "Invalid order number");
      if (kind === "check") {
        const payment = await dependencies.backend.staffPayment(
          request,
          orderNo,
        );
        const provider = dependencies.provider();
        if (provider.name !== payment.provider)
          throw new PaymentError(
            409,
            "Select the provider used by this checkout before checking payment",
          );
        const confirmation = await provider.confirm({
          url: new URL(request.url),
          headers: request.headers,
          rawBody: "",
          inquiry: payment,
        });
        if (!confirmation.valid || !confirmation.event)
          throw new PaymentError(
            409,
            "Payment has not been confirmed by the provider",
          );
        if (
          confirmation.event.orderNo !== orderNo ||
          confirmation.event.providerRef !== payment.providerRef
        )
          throw new PaymentError(
            409,
            "Provider response does not match this checkout",
          );
        return json(
          await dependencies.backend.apply(provider.name, confirmation.event),
        );
      }
      const order = await dependencies.backend.customerOrder(request, orderNo);
      if (!order.cardEnabled)
        throw new PaymentError(409, "Card and wallet payments are not available yet");
      const method = body.method;
      if (method !== "card" && method !== "wallet")
        throw new PaymentError(400, "Choose card or Easypaisa wallet");
      if (order.paymentMethod !== (method === "card" ? "card" : "easypaisa"))
        throw new PaymentError(
          409,
          "Choose the payment method saved on the order",
        );
      if (
        order.status !== "pending_payment" ||
        !order.expiresAt ||
        new Date(order.expiresAt).getTime() <= Date.now()
      ) {
        throw new PaymentError(
          409,
          "The payment window is closed. Please place a new order",
        );
      }
      paisa(order.amount);
      const provider = dependencies.provider();
      const returnUrl = new URL("/checkout/return", origin);
      returnUrl.searchParams.set("orderNo", orderNo);
      const checkout = await provider.createCheckout({
        orderNo,
        amount: order.amount,
        currency: "PKR",
        method,
        phone: order.phone,
        email: order.email,
        returnUrl: returnUrl.href,
        expiresAt: order.expiresAt,
      });
      await dependencies.backend.initiate(
        order,
        provider.name,
        checkout.providerRef,
        method,
      );
      return json({
        redirectUrl: checkout.redirectUrl,
        ...(checkout.formFields ? { formFields: checkout.formFields } : {}),
      });
    } catch (error) {
      if (error instanceof PaymentError)
        return json({ error: error.message }, error.status);
      // Do not expose SDK/network errors, raw provider bodies, JWTs or secrets.
      console.error("Payment request failed", {
        function: kind,
        category: "internal",
      });
      return json(
        {
          error:
            "Payment service is unavailable. Please try again or contact the shop",
        },
        503,
      );
    }
  };
}
