import { ShipmentTracking } from "./ShipmentTracking";
import { StaffReturnRequest } from "./StaffReturnRequest";
import { Input } from "@/components/ui/input";
import { DataTable } from "@/components/shared/DataTable";
import { useRef, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useApp } from "../../context/SupabaseAppContext";
import { queryKeys, invalidateProducts } from "../../lib/queryClient";
import { onlineOrdersService } from "../../lib/services";
import { allowedOnlineActions, onlineLabel } from "../../lib/onlineOrders";
import { getErrorMessage } from "../../lib/errors";
import { swalConfig } from "../../lib/sweetAlert";
import { ParcelReturn } from "./ParcelReturn";
import { PackingSlip } from "./PackingSlip";
import { printSlip } from "./printSlip";
export function OnlineOrderDetail({
  id,
  onBack,
}: {
  id: string;
  onBack: () => void;
}) {
  const { state } = useApp();
  const user = state.currentUser;
  const client = useQueryClient();
  const query = useQuery({
    queryKey: queryKeys.onlineOrder(user?.id ?? "", id),
    queryFn: () => onlineOrdersService.detail(id),
    refetchInterval: 30_000,
    enabled: !!user && ["admin", "manager", "cashier"].includes(user.role),
  });
  const locations = useQuery({
    queryKey: queryKeys.onlineLocations,
    queryFn: onlineOrdersService.locations,
  });
  const [busy, setBusy] = useState(false),
    [error, setError] = useState(""),
    [courier, setCourier] = useState(""),
    [tracking, setTracking] = useState(""),
    [reason, setReason] = useState(""),
    [method, setMethod] = useState<"cash" | "card">("cash"),
    [tendered, setTendered] = useState(""),
    [reference, setReference] = useState("");
  const pending = useRef<{
    action: string;
    request_id: string;
    payload: Record<string, unknown>;
  } | null>(null);
  if (query.isLoading)
    return (
      <p className="p-6" role="status">
        Loading order…
      </p>
    );
  if (query.error)
    return (
      <div className="p-6">
        <button onClick={onBack} className="btn btn-secondary btn-md">
          Back
        </button>
        <p role="alert">{getErrorMessage(query.error)}</p>
      </div>
    );
  const order = query.data;
  if (!order || !user) return null;
  const actions = allowedOnlineActions(order, user.role),
    money = (n: number) => `${state.settings.currency} ${n.toFixed(2)}`;
  async function run(action: string, extra: Record<string, unknown> = {}) {
    if (busy || !order) return;
    setError("");
    if (action === "cancel" && !reason.trim()) {
      setError("Enter a cancellation reason");
      return;
    }
    if (action === "shipped" && (!courier.trim() || !tracking.trim())) {
      setError("Enter the courier and tracking number");
      return;
    }
    if (
      action === "collect" &&
      method === "cash" &&
      tendered &&
      (Number(tendered) < order.total || !Number.isFinite(Number(tendered)))
    ) {
      setError("Cash received must cover the order total");
      return;
    }
    if (action === "packed" || action === "refund" || action === "cancel") {
      const result = await swalConfig.confirm(
        action === "packed"
          ? "Pack and fulfil order"
          : action === "refund"
            ? "Record portal refund"
            : "Cancel order",
        action === "packed"
          ? "Packing deducts the reserved stock and creates the sale."
          : action === "refund"
            ? "Confirm the full refund was sent through the payment provider portal. This records it only."
            : "This releases the reserved items. Captured payments need a provider refund.",
        "Confirm",
      );
      if (!result.isConfirmed) return;
    }
    setBusy(true);
    try {
      if (action === "check") await onlineOrdersService.check(order.order_no);
      else {
        // Preserve uncertain posts exactly until they succeed. Editing the form
        // must not change the intent behind a retry's idempotency key.
        if (pending.current && pending.current.action !== action)
          throw new Error(
            "Retry the previous action first, or refresh to review its outcome",
          );
        const saved = pending.current ?? {
          action,
          request_id: crypto.randomUUID(),
          payload: extra,
        };
        pending.current = saved;
        const p = { id, request_id: saved.request_id, ...saved.payload };
        if (action === "cancel")
          await onlineOrdersService.cancel(
            p as import("../../lib/database.types").Json,
          );
        else if (action === "collect")
          await onlineOrdersService.collect(
            p as import("../../lib/database.types").Json,
          );
        else if (action === "refund")
          await onlineOrdersService.refund(
            p as import("../../lib/database.types").Json,
          );
        else
          await onlineOrdersService.advance(
            p as import("../../lib/database.types").Json,
          );
        pending.current = null;
      }
      if (action === "cancel") invalidateProducts();
      if (action === "packed") {
        invalidateProducts();
        void client.invalidateQueries({ queryKey: queryKeys.sales });
        void client.invalidateQueries({ queryKey: queryKeys.allReports });
      }
      if (action === "collect")
        void client.invalidateQueries({ queryKey: queryKeys.cashShift });
      await client.invalidateQueries({ queryKey: queryKeys.onlineOrders });
      await swalConfig.success("Order updated");
    } catch (error) {
      if (
        error &&
        typeof error === "object" &&
        "code" in error &&
        error.code === "P0001"
      )
        pending.current = null;
      setError(getErrorMessage(error));
    } finally {
      setBusy(false);
    }
  }
  const names: Record<string, string> = {
    confirmed: "Confirm",
    packed: "Pack and fulfil",
    ready_for_pickup: "Ready for pickup",
    shipped: "Shipped",
    delivered: "Delivered",
  };
  const whatsapp = `https://wa.me/${order.phone.replace(/\D/g, "")}?text=${encodeURIComponent(`Your order ${order.order_no}: ${onlineLabel(order.status)}.`)}`;
  return (
    <section className="online-detail grid lg:grid-cols-2 gap-5 max-w-6xl">
      <div className="flex flex-wrap items-center gap-3">
        <button className="btn btn-secondary btn-md" onClick={onBack}>
          Back to orders
        </button>
        <h1 className="text-2xl font-bold">{order.order_no}</h1>
        <button
          className="btn btn-secondary btn-md"
          onClick={() => {
            pending.current = null;
            void query.refetch();
          }}
        >
          Refresh
        </button>
        <button className="btn btn-secondary btn-md" onClick={printSlip}>
          Print packing slip
        </button>
        <a
          className="btn btn-secondary btn-md"
          href={whatsapp}
          target="_blank"
          rel="noopener noreferrer"
        >
          WhatsApp customer
        </a>
      </div>
      <div className="card p-5 space-y-2">
        <p className="font-semibold">
          {order.contact_name} · {order.phone}
        </p>
        <p>{order.email}</p>
        <p>
          {onlineLabel(order.fulfilment)}{" "}
          {Object.values(order.address ?? {})
            .filter(Boolean)
            .join(", ")}
        </p>
        <p>
          {onlineLabel(order.status)} · {onlineLabel(order.payment_status)} ·{" "}
          {order.payment_method === "easypaisa"
            ? "Easypaisa wallet"
            : order.payment_method === "cod"
              ? "Cash on delivery"
              : "Card"}
        </p>
        <p className="font-bold">Total: {money(order.total)}</p>
        {order.notes_customer && <p>Customer note: {order.notes_customer}</p>}
        {order.notes_staff && (
          <p className="bg-lightwarning p-3">Staff note: {order.notes_staff}</p>
        )}
        {order.tracking_no && (
          <p>
            {order.courier} · Tracking {order.tracking_no}
          </p>
        )}
      </div>
      {order.payments.some((p) => p.needs_refund) && (
        <p
          role="alert"
          className="bg-lightwarning text-warning p-4 border border-warning"
        >
          Payment needs refund. Review the payment provider portal before
          sending money.
        </p>
      )}
      {locations.error && (
        <p role="alert">
          Picking locations could not be loaded:{" "}
          {getErrorMessage(locations.error)}
        </p>
      )}
      <div className="card overflow-x-auto">
        <DataTable className="table">
          <thead className="table-header">
            <tr>
              {["Item", "Quantity", "Pick from", "Total"].map((s) => (
                <th className="table-header-cell" key={s}>
                  {s}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {order.lines.map((line) => (
              <tr key={line.id}>
                <td className="table-cell">
                  {line.description}
                  <span className="block text-xs">
                    {[line.size, line.color, line.sku]
                      .filter(Boolean)
                      .join(" · ")}
                  </span>
                </td>
                <td className="table-cell">
                  {line.quantity} {line.unit}
                </td>
                <td className="table-cell">
                  {locations.data?.find((l) => l.id === line.location_id)
                    ?.name ??
                    (locations.isLoading ? "Loading…" : line.location_id)}
                </td>
                <td className="table-cell">{money(line.total)}</td>
              </tr>
            ))}
          </tbody>
        </DataTable>
      </div>
      {error && (
        <p role="alert" className="text-error">
          {error}
        </p>
      )}
      <div className="card p-5 flex flex-col gap-4">
        <h2 className="font-bold text-lg">Actions</h2>
        {actions.next === "shipped" && (
          <div className="flex flex-wrap gap-3">
            <label className="flex flex-col gap-1.5">
              Courier
              <Input
                className="input"
                value={courier}
                onChange={(e) => setCourier(e.target.value)}
                maxLength={100}
              />
            </label>
            <label className="flex flex-col gap-1.5">
              Tracking number
              <Input
                className="input"
                value={tracking}
                onChange={(e) => setTracking(e.target.value)}
                maxLength={100}
              />
            </label>
          </div>
        )}
        {(actions.next ||
          order.payments.some((p) => p.status === "initiated")) && (
          <div className="flex flex-wrap gap-3">
            {actions.next && (
              <button
                disabled={busy}
                className="btn btn-primary btn-md"
                onClick={() =>
                  void run(actions.next!, {
                    status: actions.next,
                    courier,
                    tracking_no: tracking,
                  })
                }
              >
                {names[actions.next]}
              </button>
            )}
            {order.payments.some((p) => p.status === "initiated") && (
              <button
                className="btn btn-secondary btn-md"
                disabled={busy}
                onClick={() => void run("check")}
              >
                Check payment status
              </button>
            )}
          </div>
        )}
        {actions.collect && (
          <div className="flex flex-col items-start gap-3 border-t border-border pt-4">
            <h3 className="font-semibold">
              Collect COD payment · {money(order.total)}
            </h3>
            <label className="flex flex-col gap-1.5 w-full">
              Method
              <select
                className="select"
                value={method}
                onChange={(e) => setMethod(e.target.value as "cash" | "card")}
              >
                <option value="cash">Cash</option>
                <option value="card">Card</option>
              </select>
            </label>
            {method === "cash" ? (
              <label className="flex flex-col gap-1.5 w-full">
                Cash received
                <Input
                  className="input"
                  type="number"
                  min={order.total}
                  step="0.01"
                  value={tendered}
                  onChange={(e) => setTendered(e.target.value)}
                  placeholder={order.total.toFixed(2)}
                />
              </label>
            ) : (
              <label className="flex flex-col gap-1.5 w-full">
                Card payment reference
                <Input
                  className="input"
                  value={reference}
                  onChange={(e) => setReference(e.target.value)}
                />
              </label>
            )}
            <button
              className="btn btn-primary btn-md"
              disabled={busy}
              onClick={() =>
                void run("collect", {
                  payments: [
                    {
                      method,
                      amount: order.total,
                      ...(method === "cash"
                        ? { tendered: Number(tendered || order.total) }
                        : { reference }),
                    },
                  ],
                })
              }
            >
              Collect payment
            </button>
          </div>
        )}
        {actions.cancel && (
          <div className="flex flex-col items-start gap-3 border-t border-border pt-4">
            <label className="flex flex-col gap-1.5 w-full">
              Cancellation reason
              <Input
                className="input"
                maxLength={2000}
                value={reason}
                onChange={(e) => setReason(e.target.value)}
              />
            </label>
            <button
              className="btn btn-danger btn-md"
              disabled={busy}
              onClick={() => void run("cancel", { reason })}
            >
              Cancel order
            </button>
          </div>
        )}
        {actions.refund &&
          order.payments
            .filter((p) => ["paid", "failed"].includes(p.status))
            .map((payment) => (
              <div
                className="flex flex-col items-start gap-3 border-t border-border pt-4"
                key={payment.id}
              >
                <p>
                  {payment.provider_ref} · {money(payment.amount)} ·{" "}
                  {onlineLabel(payment.status)}
                </p>
                <button
                  className="btn btn-secondary btn-md"
                  disabled={busy}
                  onClick={() =>
                    void run("refund", { provider_ref: payment.provider_ref })
                  }
                >
                  Record refund
                </button>
              </div>
            ))}
      </div>
      {["admin", "manager"].includes(user.role) && (
        <StaffReturnRequest orderId={order.id} userId={user.id} />
      )}
      <ShipmentTracking
        key={order.id + ":" + order.tracking_version + ":" + order.status}
        order={order}
      />
      <ParcelReturn key={order.id} order={order} role={user.role} />
      <div className="card p-5">
        <h2 className="font-bold mb-4">Timeline</h2>
        <ol className="space-y-5 border-l-2 border-lightprimary ml-2 pl-6">
          {order.events.map((event) => (
            <li
              key={event.id}
              className="relative before:absolute before:w-3 before:h-3 before:rounded-full before:bg-primary before:-left-[31px] before:top-1"
            >
              <p>{event.public_message ?? onlineLabel(event.event)}</p>
              <time className="text-xs text-bodytext">
                {new Date(event.created_at).toLocaleString()}
              </time>
            </li>
          ))}
        </ol>
      </div>
      <div className="hidden">
        <PackingSlip
          order={order}
          storeName={state.settings.storeName}
          currency={state.settings.currency}
        />
      </div>
    </section>
  );
}
