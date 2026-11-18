import Link from "next/link";
import { ArrowUpRight, ShoppingBag } from "lucide-react";
import { statusLabel, type WebOrder } from "@/lib/orders";
import { formatPrice } from "@/lib/helpers";

type OrderSummary = Pick<
  WebOrder,
  "order_no" | "status" | "payment_status" | "total"
>;
export function CustomerOrders({ orders }: { orders: OrderSummary[] }) {
  return (
    <section className="lv-orders-page">
      <p className="lv-eyebrow">YOUR BICYCLES.PK FINDS</p>
      <h1>My orders</h1>
      <p className="lv-account-intro">
        Follow your orders and revisit your favourites.
      </p>
      <Link className="underline" href="/account/track">
        Track an order by number
      </Link>
      {orders.length ? (
        <ul className="lv-order-cards">
          {orders.map((order) => (
            <li key={order.order_no}>
              <Link
                href={`/account/orders/${order.order_no}`}
                aria-label={`View order ${order.order_no}`}
              >
                <div className="lv-order-card-top">
                  <strong>{order.order_no}</strong>
                  <ArrowUpRight size={20} aria-hidden="true" />
                </div>
                <div className="lv-order-card-bottom">
                  <div>
                    <span className="lv-order-status">
                      {statusLabel(order.status)}
                    </span>
                    <span className="lv-order-payment">
                      Payment:{" "}
                      {order.payment_status === "cod"
                        ? "Due"
                        : statusLabel(order.payment_status)}
                    </span>
                  </div>
                  <b>{formatPrice(order.total)}</b>
                </div>
                <span className="lv-order-view">Track & view order</span>
              </Link>
            </li>
          ))}
        </ul>
      ) : (
        <div className="lv-account-empty">
          <ShoppingBag size={36} strokeWidth={1} aria-hidden="true" />
          <h2>A little something to look forward to.</h2>
          <p>Your orders will appear here once you find your favourites.</p>
          <Link className="lv-button" href="/collections">
            Explore the collections <ArrowUpRight size={17} />
          </Link>
        </div>
      )}
    </section>
  );
}
