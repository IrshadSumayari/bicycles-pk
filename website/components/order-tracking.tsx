"use client";
import Link from "next/link";
import { useState } from "react";
import type { WebOrder } from "@/lib/orders";
import { courierTrackingPage, orderProgress } from "../../shared/orderTracking";
import { Button } from "./ui/button";
export function OrderTracking({ order }: { order: WebOrder }) {
  const progress = orderProgress(order.status, order.fulfilment),
    courier = courierTrackingPage(order.courier);
  const latest = order.events
    .filter((e) => e.event.startsWith("shipment_"))
    .at(-1);
  const [copied, setCopied] = useState("");
  async function copy() {
    try {
      await navigator.clipboard.writeText(order.tracking_no ?? "");
      setCopied("Tracking number copied.");
    } catch {
      setCopied("Select and copy the tracking number shown above.");
    }
  }
  return (
    <section
      className="lv-order-panel lv-tracking-panel"
      aria-labelledby="order-tracking-title"
    >
      <h2 id="order-tracking-title">Track your order</h2>
      <p>
        {order.fulfilment === "pickup"
          ? "Pickup updates recorded by LadyVogue."
          : "Order updates recorded by LadyVogue. For the courier’s latest scans, use its tracking page below."}
      </p>
      {progress.notice && (
        <p className="lv-tracking-notice">{progress.notice}</p>
      )}
      <ol className="lv-tracking-steps" aria-label="Order progress">
        {progress.steps.map((s) => (
          <li
            key={s.key}
            data-state={s.state}
            aria-current={s.state === "current" ? "step" : undefined}
          >
            <span aria-hidden="true">{s.state === "complete" ? "✓" : "○"}</span>
            <div>
              <strong>{s.label}</strong>
              <small>
                {s.state === "complete"
                  ? "Completed"
                  : s.state === "current"
                    ? "Current stage"
                    : progress.stopped
                      ? "Not confirmed"
                      : "Pending"}
              </small>
            </div>
          </li>
        ))}
      </ol>
      {order.fulfilment === "pickup" ? (
        <p>
          {order.status === "ready_for_pickup"
            ? "Your order is ready for collection. Contact us to arrange pickup."
            : order.status === "delivered"
              ? "This pickup order has been collected."
              : "This order is for pickup. Please wait until it is ready before visiting."}
        </p>
      ) : order.tracking_no ? (
        <div className="lv-tracking-shipment">
          <p>
            <strong>{order.courier || "Courier"} · Tracking number</strong>
            <code>{order.tracking_no}</code>
          </p>
          <Button
            type="button"
            variant="outline"
            className="lv-tracking-action"
            onClick={() => void copy()}
          >
            Copy tracking number
          </Button>
          <p role="status">{copied}</p>
          {courier ? (
            <>
              <a
                className="underline"
                href={courier.url}
                target="_blank"
                rel="noopener noreferrer"
                referrerPolicy="no-referrer"
              >
                Open {courier.name} tracking ↗
              </a>
              <p>
                Opens the courier’s website. Enter the tracking number there.
                New shipments may take time to appear.
              </p>
            </>
          ) : (
            <p>
              <Link href="/pages/contact">Contact us</Link> for help tracking
              this courier.
            </p>
          )}
        </div>
      ) : (
        <p>Your courier and tracking number will appear after dispatch.</p>
      )}
      {latest && (
        <div className="lv-tracking-notice">
          <strong>Latest delivery update</strong>
          <p className="whitespace-pre-wrap">{latest.message}</p>
          <time dateTime={latest.created_at}>
            {new Date(latest.created_at).toLocaleString("en-PK", {
              timeZone: "Asia/Karachi",
            })}
          </time>
        </div>
      )}
      <p>
        <Link href="/pages/contact">Need help with your order?</Link>
      </p>
    </section>
  );
}
