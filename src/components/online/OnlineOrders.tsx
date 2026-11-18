import { ReturnInbox } from "./ReturnInbox";
import { Input } from "@/components/ui/input";
import { StatusBadge } from "@/components/shared/StatusBadge";
import { DataTable } from "@/components/shared/DataTable";
import { useEffect, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { useApp } from "../../context/SupabaseAppContext";
import { queryKeys } from "../../lib/queryClient";
import { onlineOrdersService } from "../../lib/services";
import { getErrorMessage } from "../../lib/errors";
import { ONLINE_STATUSES, onlineLabel } from "../../lib/onlineOrders";
import { OnlineOrderDetail } from "./OnlineOrderDetail";
export function OnlineOrders({
  target,
}: {
  /** Set by the header bell: an order to open, or null for the list. */
  target?: { id: string | null; n: number };
} = {}) {
  const { state } = useApp();
  const user = state.currentUser;
  const [view, setView] = useState<"orders" | "returns">("orders");
  const [status, setStatus] = useState("placed"),
    [search, setSearch] = useState(""),
    [q, setQ] = useState(""),
    [offset, setOffset] = useState(0),
    [selected, setSelected] = useState<string | null>(target?.id ?? null);
  useEffect(() => {
    if (!target) return;
    setSelected(target.id);
    // The bell always lands on orders, not the returns inbox.
    setView("orders");
  }, [target]);
  const allowed = !!user && ["admin", "manager", "cashier"].includes(user.role);
  const filters = { status, q, limit: 24, offset };
  const query = useQuery({
    queryKey: queryKeys.onlineOrderList(user?.id ?? "", filters),
    queryFn: () => onlineOrdersService.list(filters),
    enabled: allowed && view === "orders",
    refetchInterval: 30_000,
  });
  if (!allowed) return <p>Online orders are for counter staff only.</p>;
  if (selected)
    return <OnlineOrderDetail id={selected} onBack={() => setSelected(null)} />;
  return (
    <section className="p-4 lg:p-6 space-y-5">
      {["admin", "manager"].includes(user.role) && (
        <div className="flex flex-wrap gap-3">
          <button
            className="btn btn-secondary btn-md"
            aria-pressed={view === "orders"}
            onClick={() => setView("orders")}
          >
            Online orders
          </button>
          <button
            className="btn btn-secondary btn-md"
            aria-pressed={view === "returns"}
            onClick={() => setView("returns")}
          >
            Return requests
          </button>
        </div>
      )}
      {view === "returns" && ["admin", "manager"].includes(user.role) ? (
        <ReturnInbox userId={user.id} onSelect={setSelected} />
      ) : (
        <>
          <div className="flex flex-wrap justify-end gap-3">
            <button
              className="btn btn-secondary btn-md"
              onClick={() => void query.refetch()}
              disabled={query.isFetching}
            >
              Refresh
            </button>
          </div>
          <form
            className="flex flex-wrap gap-3"
            onSubmit={(e) => {
              e.preventDefault();
              setQ(search.trim());
              if (search.trim()) setStatus("");
              setOffset(0);
            }}
          >
            <label>
              Status
              <select
                className="select"
                value={status}
                onChange={(e) => {
                  setStatus(e.target.value);
                  setOffset(0);
                }}
              >
                <option value="">All statuses</option>
                {ONLINE_STATUSES.map((s) => (
                  <option key={s} value={s}>
                    {onlineLabel(s)}
                  </option>
                ))}
              </select>
            </label>
            <label>
              Order, phone, courier or tracking number
              <Input
                className="input"
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                placeholder="Search order or shipment"
              />
            </label>
            <button className="btn btn-primary btn-md self-end">Search</button>
          </form>
          {query.isLoading && <p role="status">Loading orders…</p>}
          {query.error && <p role="alert">{getErrorMessage(query.error)}</p>}
          <div className="card overflow-x-auto">
            <DataTable className="table">
              <thead className="table-header">
                <tr>
                  {[
                    "Order",
                    "Customer",
                    "Payment",
                    "Fulfilment",
                    "Tracking",
                    "Status",
                    "Total",
                  ].map((h) => (
                    <th className="table-header-cell" key={h}>
                      {h}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {query.data?.orders.map((order) => (
                  <tr className="table-row" key={order.id}>
                    <td className="table-cell">
                      <button
                        className="text-primary underline font-mono"
                        onClick={() => setSelected(order.id)}
                      >
                        {order.order_no}
                      </button>
                    </td>
                    <td className="table-cell">
                      {order.contact_name}
                      <span className="block text-xs">{order.phone}</span>
                    </td>
                    <td className="table-cell">
                      {onlineLabel(order.payment_status)} ·{" "}
                      {onlineLabel(order.payment_method)}
                    </td>
                    <td className="table-cell">
                      {onlineLabel(order.fulfilment)}
                    </td>
                    <td className="table-cell">
                      {order.tracking_no ? (
                        <>
                          <span className="block">{order.courier}</span>
                          <code>{order.tracking_no}</code>
                        </>
                      ) : order.fulfilment === "pickup" ? (
                        "Pickup order"
                      ) : (
                        "Not entered"
                      )}
                    </td>
                    <td className="table-cell">
                      <StatusBadge status={order.status}>
                        {onlineLabel(order.status)}
                      </StatusBadge>
                    </td>
                    <td className="table-cell">
                      {state.settings.currency} {order.total.toFixed(2)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </DataTable>
            {query.data?.orders.length === 0 && (
              <p className="p-6">No orders match these filters.</p>
            )}
          </div>
          <div className="flex items-center gap-4">
            <button
              className="btn btn-secondary btn-md"
              disabled={offset === 0}
              onClick={() => setOffset((n) => Math.max(0, n - 24))}
            >
              Previous
            </button>
            <span>{query.data?.total_count ?? 0} orders</span>
            <button
              className="btn btn-secondary btn-md"
              disabled={offset + 24 >= (query.data?.total_count ?? 0)}
              onClick={() => setOffset((n) => n + 24)}
            >
              Next
            </button>
          </div>
        </>
      )}
    </section>
  );
}
