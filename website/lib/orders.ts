import { browserClient } from "./supabase-browser";
import type { CartLine } from "./cart";
import type { CheckoutForm } from "./checkout";
export type QuoteLine = CartLine & {
  unit: string;
  description: string;
  sku: string;
  size: string | null;
  color: string | null;
  unit_price: number;
  tax: number;
  total: number;
  availability: string;
};
export type OrderQuote = {
  lines: QuoteLine[];
  subtotal: number;
  discount: number;
  tax: number;
  delivery_fee: number;
  total: number;
  cod_allowed: boolean;
  payment_methods: ("card" | "easypaisa" | "cod")[];
};
export type WebOrder = Omit<
  OrderQuote,
  "cod_allowed" | "payment_methods" | "lines"
> & {
  lines: (Omit<QuoteLine, "availability"> & { line_no: number })[];
  order_no: string;
  status: string;
  payment_status: string;
  payment_method: string;
  contact_name: string;
  phone: string;
  fulfilment: string;
  address: CheckoutForm["address"] | null;
  expires_at: string | null;
  tracking_no: string | null;
  courier: string | null;
  events: { event: string; message: string; created_at: string }[];
};
export const statusLabel = (value: string) =>
  value.replaceAll("_", " ").replace(/^./, (l) => l.toUpperCase());
export const ordersService = {
  async quote(lines: CartLine[], fulfilment: string): Promise<OrderQuote> {
    const { data, error } = await browserClient().rpc("quote_online_order", {
      p: { lines, fulfilment },
    });
    if (error) throw error;
    return data as unknown as OrderQuote;
  },
  async create(
    form: CheckoutForm,
    lines: CartLine[],
    request_id: string,
  ): Promise<{ order_no: string }> {
    const { data, error } = await browserClient().rpc("create_online_order", {
      p: { ...form, lines, request_id },
    });
    if (error) throw error;
    return data as unknown as { order_no: string };
  },
  async detail(orderNo: string): Promise<WebOrder> {
    const { data, error } = await browserClient().rpc("my_online_order", {
      p_order_no: orderNo,
    });
    if (error) throw error;
    return data as unknown as WebOrder;
  },
  async cancel(orderNo: string) {
    const { error } = await browserClient().rpc("cancel_my_online_order", {
      p_order_no: orderNo,
    });
    if (error) throw error;
  },
  async payment(orderNo: string, method: string) {
    const { data, error } = await browserClient().functions.invoke(
      "payment-create",
      { body: { orderNo, method: method === "easypaisa" ? "wallet" : "card" } },
    );
    if (error) {
      if ("context" in error && error.context instanceof Response) {
        const body = await error.context.json().catch(() => null);
        if (body?.error) throw new Error(body.error);
      }
      throw error;
    }
    const checkout = data as {
      redirectUrl: string;
      formFields?: Record<string, string>;
    };
    const target = new URL(checkout.redirectUrl);
    if (
      target.protocol !== "https:" &&
      !(
        target.protocol === "http:" &&
        ["localhost", "127.0.0.1"].includes(target.hostname)
      )
    )
      throw new Error("Payment address is unavailable");
    if (checkout.formFields) {
      const form = document.createElement("form");
      form.method = "POST";
      form.action = target.href;
      for (const [name, value] of Object.entries(checkout.formFields)) {
        const input = document.createElement("input");
        input.type = "hidden";
        input.name = name;
        input.value = value;
        form.appendChild(input);
      }
      document.body.appendChild(form);
      HTMLFormElement.prototype.submit.call(form);
    } else window.location.assign(target.href);
  },
};
