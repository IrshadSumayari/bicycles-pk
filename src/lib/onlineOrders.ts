import type { Database } from "./database.types";
type Tables = Database["public"]["Tables"];
export type OnlineOrderRow = Tables["online_orders"]["Row"];
export type OnlineOrder = Omit<OnlineOrderRow, "address"> & {
  address: Record<string, string | null> | null;
  lines: Tables["online_order_lines"]["Row"][];
  payments: Tables["online_payments"]["Row"][];
  events: Tables["online_order_events"]["Row"][];
};
export const ONLINE_STATUSES = [
  "pending_payment",
  "placed",
  "confirmed",
  "packed",
  "ready_for_pickup",
  "shipped",
  "delivered",
  "cancelled",
  "expired",
  "returned_to_sender",
] as const;
export const onlineLabel = (value: string) =>
  value.replaceAll("_", " ").replace(/^./, (l) => l.toUpperCase());
export function allowedOnlineActions(
  order: Pick<
    OnlineOrderRow,
    "status" | "payment_method" | "payment_status" | "fulfilment" | "sale_id"
  >,
  role: string,
) {
  const counter = ["admin", "manager", "cashier"].includes(role);
  if (!counter)
    return { next: null, collect: false, cancel: false, refund: false };
  const canPrepare =
    order.payment_method === "cod" || order.payment_status === "paid";
  const transitions: Record<string, string> = {
    placed: "confirmed",
    confirmed: "packed",
    packed: order.fulfilment === "pickup" ? "ready_for_pickup" : "shipped",
    ready_for_pickup: "delivered",
    shipped: "delivered",
  };
  const next =
    canPrepare &&
    (!["ready_for_pickup", "shipped"].includes(order.status) ||
      order.payment_status === "paid")
      ? (transitions[order.status] ?? null)
      : null;
  return {
    next,
    collect:
      order.payment_method === "cod" &&
      order.payment_status !== "paid" &&
      !!order.sale_id &&
      ["ready_for_pickup", "shipped"].includes(order.status),
    cancel:
      !order.sale_id &&
      ["pending_payment", "placed", "confirmed"].includes(order.status),
    refund: ["admin", "manager"].includes(role),
  };
}
