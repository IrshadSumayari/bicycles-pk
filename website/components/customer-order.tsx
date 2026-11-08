"use client";
import { CustomerReturnRequest } from "./customer-return-request";
import { OrderTracking } from "./order-tracking";
import { Button } from "./ui/button";
import Link from "next/link";
import { useEffect, useState } from "react";
import { ordersService, statusLabel, type WebOrder } from "@/lib/orders";
import { countdown } from "@/lib/checkout";
import { formatPrice } from "@/lib/helpers";
import { getErrorMessage } from "@/lib/errors";
import { QuoteTotals } from "./cart-quote";
export function CustomerOrder({
  initial,
  mode = "detail",
}: {
  initial: WebOrder;
  mode?: "detail" | "return" | "cancel";
}) {
  const [order, setOrder] = useState(initial),
    [error, setError] = useState(""),
    [busy, setBusy] = useState(false),
    [timedOut, setTimedOut] = useState(false),
    [refreshing, setRefreshing] = useState(false),
    [checkedAt, setCheckedAt] = useState<string | null>(null);
  const [now, setNow] = useState<number | null>(null);
  useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(timer);
  }, []);
  useEffect(() => {
    if (mode !== "return") return;
    let live = true,
      count = 0,
      inFlight = false;
    const deadline = setTimeout(() => {
      clearInterval(timer);
      if (live) setTimedOut(true);
    }, 60_000);
    const timer = setInterval(async () => {
      if (inFlight) return;
      if (++count >= 30) clearInterval(timer);
      inFlight = true;
      try {
        const next = await ordersService.detail(initial.order_no);
        if (live) {
          setError("");
          setOrder(next);
          if (
            next.payment_status === "paid" ||
            ["cancelled", "expired"].includes(next.status)
          ) {
            clearInterval(timer);
            clearTimeout(deadline);
          }
        }
      } catch (error) {
        if (live) setError(getErrorMessage(error));
      } finally {
        inFlight = false;
      }
    }, 2000);
    return () => {
      live = false;
      clearInterval(timer);
      clearTimeout(deadline);
    };
  }, [mode, initial.order_no]);
  async function refreshOrder() {
    if (refreshing || busy) return;
    setRefreshing(true);
    try {
      setOrder(await ordersService.detail(order.order_no));
      setCheckedAt(
        new Date().toLocaleTimeString("en-PK", { timeZone: "Asia/Karachi" }),
      );
      setError("");
    } catch (e) {
      setError(getErrorMessage(e));
    } finally {
      setRefreshing(false);
    }
  }
  async function action(cancel: boolean) {
    setBusy(true);
    setError("");
    try {
      if (cancel) {
        if (
          !window.confirm(
            "Cancel this order? Captured payments will need a shop refund.",
          )
        )
          return;
        await ordersService.cancel(order.order_no);
        setOrder(await ordersService.detail(order.order_no));
      } else await ordersService.payment(order.order_no, order.payment_method);
    } catch (error) {
      setError(getErrorMessage(error));
    } finally {
      setBusy(false);
    }
  }
  const activeHold =
    order.status === "pending_payment" &&
    !!order.expires_at &&
    now !== null &&
    Date.parse(order.expires_at) > now;
  return (
    <article className="lv-order-detail space-y-6">
      <header className="lv-order-heading">
        <p className="lv-eyebrow">YOUR ORDER</p>
        <h1>{order.order_no}</h1>
      </header>
      {(mode === "return" || mode === "cancel") &&
        (order.payment_status === "paid" ? (
          <p role="status" className="text-xl">
            Payment confirmed. Thank you for your order.
          </p>
        ) : mode === "return" && order.status === "pending_payment" ? (
          <p role="status">
            {timedOut
              ? "We are confirming your payment"
              : "Checking your payment…"}
          </p>
        ) : null)}
      {mode === "cancel" && order.status === "pending_payment" && (
        <p>
          Your payment was not completed. Your items remain reserved until the
          payment hold expires.
        </p>
      )}
      <p className="lv-order-status-line">
        {statusLabel(order.status)} ·{" "}
        {order.payment_status === "cod"
          ? "Payment due"
          : statusLabel(order.payment_status)}{" "}
        ·{" "}
        {order.payment_method === "cod"
          ? "Cash on delivery"
          : order.payment_method === "easypaisa"
            ? "Easypaisa wallet"
            : "Card"}
      </p>
      <OrderTracking
        key={order.order_no + ":" + order.courier + ":" + order.tracking_no}
        order={order}
      />
      <div className="lv-tracking-refresh">
        <Button
          variant="outline"
          className="lv-tracking-action"
          disabled={refreshing || busy}
          onClick={() => void refreshOrder()}
        >
          {refreshing ? "Refreshing…" : "Refresh order status"}
        </Button>
        <p role="status">
          {checkedAt
            ? "Last checked at " + checkedAt + " (Pakistan time)."
            : "Refresh to check for new updates."}
        </p>
      </div>
      {order.expires_at && order.status === "pending_payment" && (
        <p aria-live="off">
          Payment hold:{" "}
          <strong>
            {now === null ? "Checking…" : countdown(order.expires_at, now)}
          </strong>
        </p>
      )}
      {order.status === "expired" && (
        <p>
          This order expired and its items were released.{" "}
          <Link href="/search">Start a new order</Link>.
        </p>
      )}
      {activeHold && (
        <Button className="" disabled={busy} onClick={() => void action(false)}>
          Retry payment
        </Button>
      )}
      {error && (
        <p role="alert" className="text-red-800">
          {error}
        </p>
      )}
      <section className="lv-order-panel" aria-labelledby="order-items-title">
        <h2 id="order-items-title">Your selection</h2>
        <ul className="lv-order-items">
          {order.lines.map((line, i) => (
            <li key={i}>
              <div>
                <strong>{line.description}</strong>
                <p>{[line.size, line.color].filter(Boolean).join(" · ")}</p>
                <small>SKU: {line.sku}</small>
              </div>
              <div className="lv-order-item-amount">
                <span>Qty {line.quantity}</span>
                <b>{formatPrice(line.total)}</b>
              </div>
            </li>
          ))}
        </ul>
      </section>
      <section
        className="lv-order-panel lv-order-totals"
        aria-labelledby="order-total-title"
      >
        <h2 id="order-total-title">Order total</h2>
        <QuoteTotals quote={order} />
      </section>
      <section
        className="lv-order-panel lv-order-delivery"
        aria-labelledby="order-delivery-title"
      >
        <h2 id="order-delivery-title">Delivery details</h2>
        <p>
          {order.fulfilment === "pickup" ? "Store pickup" : "Courier delivery"}{" "}
          · {order.contact_name} · {order.phone}
        </p>
        {order.address && (
          <p>{Object.values(order.address).filter(Boolean).join(", ")}</p>
        )}
      </section>
      <section className="lv-order-panel lv-order-timeline">
        <h2 className="text-2xl mb-4">Order updates</h2>
        <ol className="space-y-4 border-l pl-5">
          {order.events.map((event, i) => (
            <li key={i}>
              <p>{event.message}</p>
              <time className="text-sm muted" dateTime={event.created_at}>
                {new Date(event.created_at).toLocaleString("en-PK", {
                  timeZone: "Asia/Karachi",
                })}
              </time>
            </li>
          ))}
        </ol>
      </section>
      {mode === "detail" && (
        <CustomerReturnRequest key={order.order_no} order={order} />
      )}
      {["pending_payment", "placed"].includes(order.status) && (
        <Button
          variant="outline"
          className=""
          disabled={busy}
          onClick={() => void action(true)}
        >
          Cancel order
        </Button>
      )}
      {mode !== "detail" && (
        <Link
          className="block underline"
          href={`/account/orders/${order.order_no}`}
        >
          View your order
        </Link>
      )}
      <Link className="lv-order-back block underline" href="/account/orders">
        All orders
      </Link>
    </article>
  );
}
