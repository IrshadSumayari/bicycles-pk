import { useRef, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Input } from "@/components/ui/input";
import { onlineOrdersService } from "../../lib/services";
import type { OnlineOrder } from "../../lib/onlineOrders";
import { invalidateProducts, queryKeys } from "../../lib/queryClient";
import { getErrorMessage } from "../../lib/errors";
import { swalConfig } from "../../lib/sweetAlert";
import type { Json } from "../../lib/database.types";

export function ParcelReturn({
  order,
  role,
}: {
  order: OnlineOrder;
  role: string;
}) {
  const client = useQueryClient();
  const [reason, setReason] = useState("");
  const [cost, setCost] = useState("");
  const [received, setReceived] = useState(false);
  const [conditions, setConditions] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const pending = useRef<Json | null>(null);
  const manager = ["admin", "manager"].includes(role);
  const returned = useQuery({
    queryKey: [...queryKeys.onlineOrders, "parcel-return", order.id],
    queryFn: () => onlineOrdersService.parcelReturn(order.id),
    enabled: manager && order.status === "returned_to_sender",
  });
  if (!manager) return null;
  if (order.status === "returned_to_sender")
    return (
      <section className="card p-5 space-y-3">
        <h2 className="font-bold">Parcel returned to sender</h2>
        <p>
          No COD cash was collected or refunded. Sale value was reversed through
          the returns ledger. Only items inspected as resaleable were restocked.
        </p>
        {returned.error && (
          <p role="alert">{getErrorMessage(returned.error)}</p>
        )}
        {returned.data && (
          <>
            <p>Reason: {returned.data.reason}</p>
            <p>
              Recorded courier cost: PKR {returned.data.courier_cost.toFixed(2)}
            </p>
          </>
        )}
        <p className="text-sm text-bodytext">
          Courier cost is recorded for reconciliation; this does not post a cash
          expense or pay the courier.
        </p>
      </section>
    );
  if (order.status !== "shipped" || order.fulfilment !== "delivery")
    return null;
  if (order.payment_method !== "cod" || order.payment_status !== "cod")
    return (
      <section className="card p-5">
        <h2 className="font-bold">Returned parcel</h2>
        <p>
          This order has a payment. Use the sales return/refund workflow to
          inspect stock and reconcile the actual refund.
        </p>
      </section>
    );
  async function submit(event: React.FormEvent) {
    event.preventDefault();
    if (busy || !received) return;
    const confirmation = await swalConfig.confirm(
      "Receive returned parcel",
      "Confirm the whole parcel is physically back and every item has been inspected. Only resaleable items will return to stock. No cash refund will be created.",
      "Receive parcel",
    );
    if (!confirmation.isConfirmed) return;
    setBusy(true);
    setError("");
    try {
      pending.current ??= {
        id: order.id,
        request_id: crypto.randomUUID(),
        reason: reason.trim(),
        courier_cost: Number(cost),
        lines: order.lines.map((line) => ({
          variant_id: line.variant_id,
          condition: conditions[line.variant_id],
        })),
      };
      await onlineOrdersService.receiveParcel(pending.current);
      pending.current = null;
      invalidateProducts();
      await Promise.all([
        client.invalidateQueries({ queryKey: queryKeys.onlineOrders }),
        client.invalidateQueries({ queryKey: queryKeys.sales }),
        client.invalidateQueries({ queryKey: queryKeys.allReports }),
      ]);
      await swalConfig.success(
        "Returned parcel received. No cash refund was created.",
      );
    } catch (err) {
      if (
        err &&
        typeof err === "object" &&
        "code" in err &&
        err.code === "P0001"
      )
        pending.current = null;
      setError(getErrorMessage(err));
    } finally {
      setBusy(false);
    }
  }
  return (
    <form
      onSubmit={(event) => void submit(event)}
      className="card p-5 space-y-4"
    >
      <h2 className="font-bold">Receive undelivered COD parcel</h2>
      <p>
        Use this after the whole parcel is back from the courier. For partial or
        missing contents, reconcile the discrepancy before receiving it here.
        Opened lingerie must pass your hygiene and resale inspection.
      </p>
      {error && (
        <p role="alert" className="text-error">
          {error}
        </p>
      )}
      <fieldset disabled={busy || !!pending.current} className="space-y-4">
        <label className="block">
          Return reason
          <Input
            className="input"
            required
            maxLength={1000}
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            placeholder="Refused, unreachable, incorrect address…"
          />
        </label>
        <label className="block">
          Total courier cost to record (PKR)
          <Input
            className="input"
            type="number"
            required
            min={0}
            step="0.01"
            value={cost}
            onChange={(e) => setCost(e.target.value)}
          />
          <span className="text-sm text-bodytext">
            Enter the actual outgoing and return charges. Use zero if none.
            Recorded only; no cash expense is posted.
          </span>
        </label>
        {order.lines.map((line) => (
          <label className="block" key={line.id}>
            {line.description} · {line.sku} · Quantity {line.quantity}
            <select
              className="select block w-full"
              required
              value={conditions[line.variant_id] ?? ""}
              onChange={(e) =>
                setConditions((v) => ({
                  ...v,
                  [line.variant_id]: e.target.value,
                }))
              }
            >
              <option value="">Choose inspected condition</option>
              <option value="resaleable">Resaleable — return to stock</option>
              <option value="damaged">Damaged — do not restock</option>
              <option value="faulty">Faulty — do not restock</option>
            </select>
          </label>
        ))}
        <label className="flex gap-3">
          <input
            type="checkbox"
            required
            checked={received}
            onChange={(e) => setReceived(e.target.checked)}
          />
          The whole parcel is physically received and inspected.
        </label>
      </fieldset>
      <button className="btn btn-primary btn-md" disabled={busy || !received}>
        {busy
          ? "Receiving…"
          : pending.current
            ? "Retry same parcel receipt"
            : "Receive parcel — no cash refund"}
      </button>
    </form>
  );
}
