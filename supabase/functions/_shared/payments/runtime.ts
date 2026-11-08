import { amountMatches, object, paymentDecision, text } from "./helpers.ts";
import { getProvider, assertPaymentEnvironment } from "./provider.ts";
import { PaymentError, type PaymentEvent, type PayMethod } from "./types.ts";
import type {
  CustomerOrder,
  PaymentBackend,
  PaymentDependencies,
} from "./handlers.ts";

export function runtimeDependencies(): PaymentDependencies {
  const env = (key: string) => Deno.env.get(key);
  assertPaymentEnvironment(env);
  const url = env("SUPABASE_URL") ?? "";
  const anon = env("SUPABASE_ANON_KEY") ?? "";
  const service = env("SUPABASE_SERVICE_ROLE_KEY") ?? "";

  // Native fetch keeps the Edge Functions free of downloaded runtime packages.
  async function request(
    path: string,
    body?: unknown,
    token = `Bearer ${service}`,
  ): Promise<unknown> {
    const response = await fetch(`${url}${path}`, {
      method: body === undefined ? "GET" : "POST",
      headers: {
        apikey: token === `Bearer ${service}` ? service : anon,
        Authorization: token,
        "Content-Type": "application/json",
      },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(10_000),
    });
    if (!response.ok) {
      // Database errors can include supplied data. Keep them server-side and
      // respond with a fixed message rather than echoing a provider credential.
      throw new PaymentError(
        response.status === 401 ? 401 : response.status === 403 ? 403 : 409,
        response.status === 401
          ? "Please sign in again"
          : "Payment could not be updated. Check the order in the shop",
      );
    }
    return response.json();
  }
  const serviceToken = () => `Bearer ${service}`;
  async function caller(
    requestInput: Request,
  ): Promise<{ id: string; token: string }> {
    const token = requestInput.headers.get("authorization") ?? "";
    if (!/^Bearer\s+\S+$/i.test(token))
      throw new PaymentError(401, "Please sign in");
    const user = object(await request("/auth/v1/user", undefined, token));
    return { id: text(user.id), token };
  }
  async function rpc(
    name: string,
    body: unknown,
    token = serviceToken(),
  ): Promise<unknown> {
    return request(`/rest/v1/rpc/${name}`, body, token);
  }
  async function rows(
    table: string,
    filters: Record<string, string>,
  ): Promise<Record<string, unknown>[]> {
    const result = await request(
      `/rest/v1/${table}?${new URLSearchParams({ ...filters, select: "*" })}`,
      undefined,
      serviceToken(),
    );
    if (!Array.isArray(result))
      throw new PaymentError(503, "Payment service is unavailable");
    return result.map(object);
  }
  async function orderRow(orderNo: string) {
    const [order] = await rows("online_orders", { order_no: `eq.${orderNo}` });
    if (!order) throw new PaymentError(404, "Order not found");
    return order;
  }
  const backend: PaymentBackend = {
    async customerOrder(input, orderNo): Promise<CustomerOrder> {
      const user = await caller(input);
      // Ownership and the website-only guard are enforced with the CALLER JWT.
      const order = object(
        await rpc("my_online_order", { p_order_no: orderNo }, user.token),
      );
      const [settings] = await rows("app_settings", { order: "created_at.asc,id.asc", limit: "1" });
      return {
        cardEnabled: settings?.online_card_enabled === true,
        accountId: user.id,
        orderNo,
        amount: Number(order.total),
        paymentMethod: text(order.payment_method),
        status: text(order.status),
        expiresAt:
          typeof order.expires_at === "string" ? order.expires_at : null,
        phone: text(order.phone),
        email: typeof order.email === "string" ? order.email : undefined,
      };
    },
    async initiate(
      order: CustomerOrder,
      provider: string,
      providerRef: string,
      method: PayMethod,
    ) {
      await rpc("initiate_online_payment", {
        p_order_no: order.orderNo,
        p_account_id: order.accountId,
        p_provider: provider,
        p_provider_ref: providerRef,
        p_method: method,
      });
    },
    async staffPayment(input, orderNo) {
      const user = await caller(input);
      if ((await rpc("is_counter_staff", {}, user.token)) !== true)
        throw new PaymentError(403, "Only counter staff can check a payment");
      const order = await orderRow(orderNo);
      if (
        (await rpc(
          "is_branch_member",
          { p_branch_id: order.branch_id },
          user.token,
        )) !== true
      )
        throw new PaymentError(403, "This order belongs to another branch");
      const [payment] = await rows("online_payments", {
        order_id: `eq.${text(order.id)}`,
        status: "eq.initiated",
        order: "created_at.desc",
        limit: "1",
      });
      if (!payment)
        throw new PaymentError(409, "There is no initiated payment to check");
      return {
        orderNo,
        providerRef: text(payment.provider_ref),
        provider: text(payment.provider),
      };
    },
    async apply(provider: string, event: PaymentEvent) {
      const order = await orderRow(event.orderNo);
      const [payment] = await rows("online_payments", {
        provider_ref: `eq.${event.providerRef}`,
        order_id: `eq.${text(order.id)}`,
      });
      if (
        !payment ||
        payment.provider !== provider ||
        payment.method !== event.method
      )
        throw new PaymentError(
          409,
          "Payment does not match an initiated checkout",
        );
      const matches = amountMatches(event.amount, order.total);
      // Only terminal replays may skip a write. SQL repeats this check under locks.
      const decision = paymentDecision(text(payment.status), event.status);
      if (decision !== "apply") {
        if (!amountMatches(event.amount, payment.amount))
          throw new PaymentError(
            409,
            "Payment amount does not match its checkout",
          );
        return {
          status: text(payment.status),
          needs_refund: payment.needs_refund === true,
        };
      }
      if (!matches && event.status === "failed")
        throw new PaymentError(
          409,
          "Payment amount does not match the order total",
        );
      const result = object(
        await rpc("record_online_payment_event", {
          p_order_no: event.orderNo,
          p_provider: provider,
          p_provider_ref: event.providerRef,
          p_amount: event.amount,
          p_method: event.method,
          p_status: event.status,
          p_raw: event.raw,
        }),
      );
      // A captured mismatch is preserved as failed + needs_refund by SQL first.
      if (!matches && event.status === "paid")
        throw new PaymentError(
          409,
          "Payment amount does not match the order total; contact the shop",
        );
      return {
        status: text(result.status),
        needs_refund: result.needs_refund === true,
      };
    },
  };
  return {
    provider: () => getProvider(env),
    backend,
    siteUrl: env("SITE_URL") ?? "",
  };
}
