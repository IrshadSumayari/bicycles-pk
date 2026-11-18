export const shipmentUpdateLabels = {
  tracking_details: "Tracking details corrected",
  in_transit: "In transit",
  out_for_delivery: "Out for delivery",
  delivery_attempted: "Delivery attempted",
  delayed: "Delivery delayed",
} as const;
export type ShipmentUpdateKind = keyof typeof shipmentUpdateLabels;
export function courierTrackingPage(
  courier: string | null | undefined,
): { name: string; url: string } | null {
  const key = (courier ?? "")
    .trim()
    .toLowerCase()
    .replace(/[^a-z]/g, "");
  if (["postex", "postexcourier"].includes(key))
    return { name: "PostEx", url: "https://postex.pk/tracking" };
  if (
    [
      "leopards",
      "leopard",
      "leapord",
      "leopardscourier",
      "leopardscourierservices",
      "leopardcourier",
    ].includes(key)
  )
    return { name: "Leopards", url: "https://pk.leopardscourier.com/" };
  return null;
}
export function orderProgress(status: string, fulfilment: string) {
  const steps = [
    { key: "placed", label: "Order received" },
    { key: "confirmed", label: "Confirmed" },
    { key: "packed", label: "Packed" },
    {
      key: fulfilment === "pickup" ? "ready_for_pickup" : "shipped",
      label: fulfilment === "pickup" ? "Ready for pickup" : "Shipped",
    },
    {
      key: "delivered",
      label: fulfilment === "pickup" ? "Collected" : "Delivered",
    },
  ];
  const index = steps.findIndex((s) => s.key === status);
  const stopped = ["cancelled", "expired", "returned_to_sender"].includes(
    status,
  );
  return {
    steps: steps.map((s, i) => ({
      ...s,
      state:
        index < 0
          ? "pending"
          : i < index
            ? "complete"
            : i === index
              ? "current"
              : "pending",
    })),
    stopped,
    notice:
      status === "pending_payment"
        ? "Waiting for payment confirmation."
        : status === "cancelled"
          ? "This order was cancelled."
          : status === "expired"
            ? "The payment window expired."
            : status === "returned_to_sender"
              ? "The parcel was returned to Bicycles.pk. Contact us about the next steps."
              : index < 0
                ? "Contact us for the current order status."
                : null,
  };
}
export function trackingUpdateError(p: {
  courier: string;
  tracking_no: string;
  message: string;
  kind: string;
}): string | null {
  if (
    !p.courier.trim() ||
    p.courier.trim().length > 100 ||
    !p.tracking_no.trim() ||
    p.tracking_no.trim().length > 100
  )
    return "Enter a courier and tracking number, each up to 100 characters.";
  if (!Object.hasOwn(shipmentUpdateLabels, p.kind))
    return "Choose a delivery update.";
  if (p.message.trim().length < 3 || p.message.trim().length > 500)
    return "Enter a customer update of 3–500 characters.";
  return null;
}
export function normalizedOrderNumber(value: string): string | null {
  const v = value.trim().toUpperCase();
  return /^WEB-[0-9]{6,20}$/.test(v) ? v : null;
}
