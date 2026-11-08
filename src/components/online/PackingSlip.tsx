import type { OnlineOrder } from "../../lib/onlineOrders";
export function PackingSlip({
  order,
  storeName,
  currency,
}: {
  order: OnlineOrder;
  storeName: string;
  currency: string;
}) {
  return (
    <div className="order-slip bg-card text-sm space-y-3">
      <h2 className="text-center font-bold">{storeName}</h2>
      <p className="font-bold text-center">Packing slip · {order.order_no}</p>
      <p>
        {order.contact_name} · {order.phone}
      </p>
      <p>
        {order.fulfilment === "pickup"
          ? "Store pickup"
          : Object.values(order.address ?? {})
              .filter(Boolean)
              .join(", ")}
      </p>
      <table>
        <tbody>
          {order.lines.map((line) => (
            <tr key={line.id}>
              <td>
                {line.description} {line.size} {line.color}
                <span className="block text-xs">{line.sku}</span>
              </td>
              <td className="text-right">
                {line.quantity} {line.unit}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
      <p className="font-bold">
        {order.payment_method === "cod" && order.payment_status !== "paid"
          ? `COD due: ${currency} ${order.total.toFixed(2)}`
          : order.payment_status === "paid"
            ? "Payment received"
            : "Payment: " + order.payment_status}
      </p>
    </div>
  );
}
