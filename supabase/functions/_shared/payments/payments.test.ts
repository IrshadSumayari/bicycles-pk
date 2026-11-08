import { describe, expect, it, vi } from "vitest";
import {
  amountMatches,
  mockStatus,
  paisa,
  paymentDecision,
  signBody,
  verifyBody,
} from "./helpers.ts";
import { MockProvider } from "./mock.ts";
import { getProvider, assertPaymentEnvironment } from "./provider.ts";
import { EasypaisaProvider } from "./easypaisa.ts";
import {
  paymentHandler,
  type CustomerOrder,
  type PaymentBackend,
} from "./handlers.ts";
import {
  PaymentError,
  type CheckoutOrder,
  type PaymentEvent,
} from "./types.ts";

const secret = "local-payment-test-secret-at-least-32-characters";
const event: PaymentEvent = {
  orderNo: "WEB-000001",
  providerRef: "mock:WEB-000001",
  amount: 117.06,
  method: "card",
  status: "paid",
  raw: {},
};
const raw = JSON.stringify(event);
const order: CustomerOrder = {
  cardEnabled: true,
  accountId: "account-a",
  orderNo: event.orderNo,
  amount: 117.06,
  paymentMethod: "card",
  status: "pending_payment",
  expiresAt: "2099-01-01T00:00:00Z",
  phone: "+923001234567",
};
const checkout: CheckoutOrder = {
  orderNo: event.orderNo,
  amount: 117.06,
  currency: "PKR",
  method: "card",
  phone: order.phone,
  returnUrl: "http://localhost:3000/checkout/return",
  expiresAt: order.expiresAt!,
};
const provider = new MockProvider(secret);
const notification = (body: string, signature: string) => ({
  url: new URL("http://localhost/payment-webhook"),
  headers: new Headers({ "x-payment-signature": signature }),
  rawBody: body,
});
function setup() {
  const backend: PaymentBackend = {
    customerOrder: vi.fn(async () => order),
    initiate: vi.fn(async () => {}),
    staffPayment: vi.fn(async () => ({
      orderNo: event.orderNo,
      providerRef: event.providerRef,
      provider: "mock",
    })),
    apply: vi.fn(async () => ({ status: "paid", needs_refund: false })),
  };
  return {
    backend,
    handler: (kind: "create" | "webhook" | "check") =>
      paymentHandler(kind, {
        backend,
        provider: () => provider,
        siteUrl: "http://localhost:3000",
      }),
  };
}
const post = (body: unknown, headers: Record<string, string> = {}) =>
  new Request("http://localhost/function", {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });

describe("money and status decisions", () => {
  it("compares paisa exactly", () => {
    expect(amountMatches("117.06", 117.06)).toBe(true);
    expect(amountMatches(117.05, 117.06)).toBe(false);
    expect(paisa("0.10")).toBe(10n);
  });
  it.each([NaN, Infinity, -1, 1.001, "1e3", "", null])(
    "rejects invalid money %s",
    (value) => expect(() => paisa(value)).toThrow(),
  );
  it.each([
    ["paid", "paid"],
    ["failed", "failed"],
    ["refunded", "refunded"],
    ["unknown", "failed"],
  ])("maps mock status %s", (code, want) =>
    expect(mockStatus(code)).toBe(want),
  );
  it.each([
    ["initiated", "paid", "apply"],
    ["initiated", "failed", "apply"],
    ["failed", "paid", "apply"],
    ["paid", "paid", "duplicate"],
    ["paid", "failed", "ignore"],
    ["paid", "refunded", "apply"],
    ["refunded", "paid", "ignore"],
  ] as const)("idempotency: %s -> %s", (current, next, want) =>
    expect(paymentDecision(current, next)).toBe(want),
  );
});
describe("raw-body authentication", () => {
  // RFC 4231 test case 2: independent documented HMAC-SHA256 vector.
  it("matches RFC 4231 HMAC-SHA256 test vector", async () =>
    expect(await signBody("Jefe", "what do ya want for nothing?")).toBe(
      "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843",
    ));
  it("accepts valid signatures", async () =>
    expect(await verifyBody(secret, raw, await signBody(secret, raw))).toBe(
      true,
    ));
  it("rejects invalid signatures", async () =>
    expect(await verifyBody(secret, raw, "0".repeat(64))).toBe(false));
  it("rejects a tampered raw body", async () =>
    expect(
      await verifyBody(secret, raw + " ", await signBody(secret, raw)),
    ).toBe(false));
  it("rejects missing or malformed signatures", async () => {
    expect(await verifyBody(secret, raw, null)).toBe(false);
    expect(await verifyBody(secret, raw, "bad")).toBe(false);
  });
  it("parses a signed notification and strips unexpected sensitive fields", async () => {
    const body = JSON.stringify({
      ...event,
      secret: "must-not-persist",
      cardNumber: "must-not-persist",
    });
    const result = await provider.confirm(
      notification(body, await signBody(secret, body)),
    );
    expect(result.valid).toBe(true);
    expect(JSON.stringify(result.event)).not.toContain("must-not-persist");
  });
  it("does not accept signed malformed events", async () => {
    const body = JSON.stringify({ ...event, amount: 1.001 });
    expect(
      (await provider.confirm(notification(body, await signBody(secret, body))))
        .valid,
    ).toBe(false);
  });
});
describe("providers", () => {
  it("mock checkout never collects card data or returns the signing secret", async () => {
    expect(await provider.createCheckout(checkout)).toEqual({
      redirectUrl: checkout.returnUrl,
      providerRef: event.providerRef,
    });
  });
  it("mock reconciliation cannot invent a successful inquiry", async () =>
    expect(
      provider.confirm({
        ...notification("", ""),
        inquiry: { orderNo: event.orderNo, providerRef: event.providerRef },
      }),
    ).rejects.toThrow("no provider inquiry API"));
  it("requires explicit provider selection and a strong mock secret", () => {
    expect(() => getProvider(() => undefined)).toThrow();
    expect(() => new MockProvider("short")).toThrow();
  });
  it("leaves Easypaisa disabled pending the official guide, as agreed", async () => {
    const deferred = new EasypaisaProvider();
    expect(
      getProvider((k) => (k === "PAYMENT_PROVIDER" ? "easypaisa" : undefined))
        .name,
    ).toBe("easypaisa");
    await expect(deferred.createCheckout(checkout)).rejects.toMatchObject({
      status: 503,
    });
    await expect(deferred.confirm(notification(raw, ""))).rejects.toMatchObject(
      { status: 503 },
    );
  });
});
describe("HTTP handlers", () => {
  it("creates checkout using server order values", async () => {
    const { backend, handler } = setup();
    const response = await handler("create")(
      post({
        orderNo: event.orderNo,
        method: "card",
        amount: 1,
        returnUrl: "https://evil.test",
      }),
    );
    expect(response.status).toBe(200);
    expect(backend.initiate).toHaveBeenCalledWith(
      order,
      "mock",
      event.providerRef,
      "card",
    );
    expect(await response.json()).toEqual({
      redirectUrl: "http://localhost:3000/checkout/return?orderNo=WEB-000001",
    });
  });
  it("creates wallet checkout only for a wallet order", async () => {
    const { backend, handler } = setup();
    vi.mocked(backend.customerOrder).mockResolvedValue({
      ...order,
      paymentMethod: "easypaisa",
    });
    expect(
      (
        await handler("create")(
          post({ orderNo: event.orderNo, method: "wallet" }),
        )
      ).status,
    ).toBe(200);
  });
  it("refuses method switching", async () =>
    expect(
      (
        await setup().handler("create")(
          post({ orderNo: event.orderNo, method: "wallet" }),
        )
      ).status,
    ).toBe(409));
  it("refuses expired checkout", async () => {
    const { backend, handler } = setup();
    vi.mocked(backend.customerOrder).mockResolvedValue({
      ...order,
      expiresAt: "2000-01-01T00:00:00Z",
    });
    expect(
      (
        await handler("create")(
          post({ orderNo: event.orderNo, method: "card" }),
        )
      ).status,
    ).toBe(409);
    expect(backend.initiate).not.toHaveBeenCalled();
  });
  it("preserves ownership refusal", async () => {
    const { backend, handler } = setup();
    vi.mocked(backend.customerOrder).mockRejectedValue(
      new PaymentError(403, "Order not found"),
    );
    expect(
      (
        await handler("create")(
          post({ orderNo: event.orderNo, method: "card" }),
        )
      ).status,
    ).toBe(403);
    expect(backend.initiate).not.toHaveBeenCalled();
  });
  it("verifies raw body before applying notification", async () => {
    const { backend, handler } = setup();
    expect(
      (
        await handler("webhook")(
          post(event, { "x-payment-signature": await signBody(secret, raw) }),
        )
      ).status,
    ).toBe(200);
    expect(backend.apply).toHaveBeenCalledOnce();
  });
  it("invalid notification never reaches the database", async () => {
    const { backend, handler } = setup();
    expect(
      (await handler("webhook")(post(event, { "x-payment-signature": "bad" })))
        .status,
    ).toBe(401);
    expect(backend.apply).not.toHaveBeenCalled();
  });
  it("reports captured amount mismatch as 4xx", async () => {
    const { backend, handler } = setup();
    vi.mocked(backend.apply).mockRejectedValue(
      new PaymentError(409, "Payment amount does not match"),
    );
    expect(
      (
        await handler("webhook")(
          post(event, { "x-payment-signature": await signBody(secret, raw) }),
        )
      ).status,
    ).toBe(409);
  });
  it("authenticates staff before provider reconciliation", async () => {
    const { backend, handler } = setup();
    vi.mocked(backend.staffPayment).mockRejectedValue(
      new PaymentError(403, "Only counter staff"),
    );
    expect(
      (await handler("check")(post({ orderNo: event.orderNo }))).status,
    ).toBe(403);
    expect(backend.apply).not.toHaveBeenCalled();
  });
  it("returns a clear mock inquiry limitation", async () =>
    expect(
      (await setup().handler("check")(post({ orderNo: event.orderNo }))).status,
    ).toBe(409));
  it("allows the separate POS origin through to staff authentication", async () => {
    const { backend, handler } = setup();
    const response = await handler("check")(
      post({ orderNo: event.orderNo }, { origin: "https://pos.example.test" }),
    );
    expect(response.status).toBe(409);
    expect(response.headers.get("access-control-allow-origin")).toBe("*");
    expect(backend.staffPayment).toHaveBeenCalledOnce();
  });
  it("rejects cross-origin checkout requests", async () =>
    expect(
      (
        await setup().handler("create")(
          post(
            { orderNo: event.orderNo, method: "card" },
            { origin: "https://evil.test" },
          ),
        )
      ).status,
    ).toBe(403));
  it("handles CORS preflight with no credentials or checkout", async () =>
    expect(
      (
        await setup().handler("create")(
          new Request("http://localhost/function", {
            method: "OPTIONS",
            headers: { origin: "http://localhost:3000" },
          }),
        )
      ).status,
    ).toBe(204));
  it("limits request size before JSON parsing", async () =>
    expect(
      (await setup().handler("webhook")(post({ data: "x".repeat(17_000) })))
        .status,
    ).toBe(413));
  it("refuses non-POST requests", async () =>
    expect(
      (
        await setup().handler("webhook")(
          new Request("http://localhost/function"),
        )
      ).status,
    ).toBe(405));
});

describe("launch payment safety", () => {
  it.each([
    "https://shop.example",
    "https://localhost.evil.test",
    "http://192.168.1.1",
    "",
    "invalid",
  ])("refuses mock startup at %s", (site) => {
    expect(() =>
      assertPaymentEnvironment(
        (k) => k === "PAYMENT_PROVIDER" ? "mock" : k === "SITE_URL" ? site : undefined,
      ),
    ).toThrow("restricted to localhost");
  });
  it.each([
    "http://localhost:3000",
    "http://127.0.0.1:3000",
    "https://localhost",
  ])("allows local mock at %s", (site) => {
    expect(() =>
      assertPaymentEnvironment(
        (k) => k === "PAYMENT_PROVIDER" ? "mock" : k === "SITE_URL" ? site : undefined,
      ),
    ).not.toThrow();
  });
  it("refuses checkout before reaching the provider while card is disabled", async () => {
    const { backend, handler } = setup();
    vi.mocked(backend.customerOrder).mockResolvedValue({
      ...order,
      cardEnabled: false,
    });
    const response = await handler("create")(
      post({ orderNo: event.orderNo, method: "card" }),
    );
    expect(response.status).toBe(409);
    expect(await response.json()).toEqual({
      error: "Card and wallet payments are not available yet",
    });
    expect(backend.initiate).not.toHaveBeenCalled();
  });
});
