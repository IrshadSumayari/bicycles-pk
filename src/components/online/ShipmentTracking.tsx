import { ComboInput } from '@/components/shared/ComboInput';
import { useRef, useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import type { OnlineOrder } from "../../lib/onlineOrders";
import { queryKeys } from "../../lib/queryClient";
import { getErrorMessage } from "../../lib/errors";
import {
  updateOrderTracking,
  type TrackingUpdate,
} from "../../lib/orderTracking";
import {
  courierTrackingPage,
  shipmentUpdateLabels,
  trackingUpdateError,
  type ShipmentUpdateKind,
} from "../../../shared/orderTracking";
export function ShipmentTracking({ order }: { order: OnlineOrder }) {
  const client = useQueryClient(),
    link = courierTrackingPage(order.courier);
  const [courier, setCourier] = useState(order.courier ?? ""),
    [tracking, setTracking] = useState(order.tracking_no ?? ""),
    [kind, setKind] = useState<ShipmentUpdateKind>("tracking_details"),
    [message, setMessage] = useState(""),
    [busy, setBusy] = useState(false),
    [frozen, setFrozen] = useState(false),
    [error, setError] = useState("");
  const pending = useRef<TrackingUpdate | null>(null);
  async function save() {
    if (busy) return;
    setError("");
    const p = pending.current ?? {
      id: order.id,
      version: order.tracking_version,
      courier,
      tracking_no: tracking,
      kind,
      message,
      request_id: crypto.randomUUID(),
    };
    const issue = trackingUpdateError(p);
    if (issue) {
      setError(issue);
      return;
    }
    pending.current = p;
    setBusy(true);
    try {
      await updateOrderTracking(p);
      pending.current = null;
      await client.invalidateQueries({ queryKey: queryKeys.onlineOrders });
      setMessage("");
    } catch (e) {
      if (
        e &&
        typeof e === "object" &&
        "code" in e &&
        ["P0001", "42501"].includes(String(e.code))
      )
        pending.current = null;
      setError(getErrorMessage(e));
    } finally {
      setBusy(false);
      setFrozen(!!pending.current);
    }
  }
  if (order.fulfilment !== "delivery") return null;
  return (
    <section className="card p-5 space-y-4">
      <h2 className="text-lg font-bold">Shipment tracking</h2>
      <p>
        Customer-facing updates recorded by staff. Courier scans are available
        on the courier’s website.
      </p>
      {order.tracking_no && (
        <p className="break-all">
          <strong>{order.courier}</strong> · {order.tracking_no}
        </p>
      )}
      {link && order.tracking_no && (
        <a
          className="underline"
          href={link.url}
          target="_blank"
          rel="noopener noreferrer"
          referrerPolicy="no-referrer"
        >
          Open {link.name} tracking ↗
        </a>
      )}
      {["shipped", "delivered", "returned_to_sender"].includes(order.status) ? (
        <form
          className="space-y-4"
          onSubmit={(e) => {
            e.preventDefault();
            void save();
          }}
        >
          <fieldset disabled={busy || frozen} className="space-y-4">
            <div className="block">
              Courier
              <ComboInput
                aria-label="Courier"
                className="input w-full"
                maxLength={100}
                value={courier}
                onChange={setCourier}
                options={["PostEx", "Leopards"]}
              />
            </div>
            <label className="block">
              Tracking number
              <input
                className="input w-full"
                maxLength={100}
                value={tracking}
                onChange={(e) => setTracking(e.target.value)}
              />
            </label>
            <label className="block">
              Update type
              <select
                className="select w-full"
                value={kind}
                onChange={(e) => setKind(e.target.value as ShipmentUpdateKind)}
              >
                {Object.entries(shipmentUpdateLabels)
                  .filter(
                    ([k]) =>
                      order.status === "shipped" || k === "tracking_details",
                  )
                  .map(([v, label]) => (
                    <option key={v} value={v}>
                      {label}
                    </option>
                  ))}
              </select>
            </label>
            <label className="block">
              Customer update
              <textarea
                className="input w-full"
                rows={3}
                maxLength={500}
                value={message}
                onChange={(e) => setMessage(e.target.value)}
                required
              />
            </label>
            <p>
              Visible to the customer. Do not enter private staff notes. This
              records tracking information; delivery completion and COD payment
              use the existing order actions.
            </p>
          </fieldset>
          {error && <p role="alert">{error}</p>}
          <button className="btn btn-primary btn-md" disabled={busy}>
            {frozen ? "Retry tracking update" : "Save tracking update"}
          </button>
        </form>
      ) : (
        <p>
          Add the courier and tracking number with the Shipped action after
          packing.
        </p>
      )}
    </section>
  );
}
