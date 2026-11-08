import { describe, it, expect } from "vitest";
import { allowedOnlineActions } from "./onlineOrders";
const order = {
  status: "placed",
  payment_method: "card",
  payment_status: "paid",
  fulfilment: "delivery",
  sale_id: null as string | null,
};
describe("online order actions", () => {
  it("maps the fulfilment path and blocks unpaid card orders", () => {
    expect(allowedOnlineActions(order, "cashier").next).toBe("confirmed");
    expect(
      allowedOnlineActions({ ...order, status: "confirmed" }, "cashier").next,
    ).toBe("packed");
    expect(
      allowedOnlineActions(
        { ...order, status: "packed", sale_id: "sale" },
        "cashier",
      ).next,
    ).toBe("shipped");
    expect(
      allowedOnlineActions(
        { ...order, status: "packed", fulfilment: "pickup" },
        "cashier",
      ).next,
    ).toBe("ready_for_pickup");
    expect(
      allowedOnlineActions({ ...order, payment_status: "unpaid" }, "cashier")
        .next,
    ).toBeNull();
  });
  it("collects COD before delivery and refuses packed cancellation", () => {
    const cod = {
      ...order,
      status: "shipped",
      payment_method: "cod",
      payment_status: "cod",
      sale_id: "sale",
    };
    expect(allowedOnlineActions(cod, "cashier")).toMatchObject({
      next: null,
      collect: true,
      cancel: false,
    });
    expect(
      allowedOnlineActions({ ...cod, payment_status: "paid" }, "cashier"),
    ).toMatchObject({ next: "delivered", collect: false });
  });
  it("restricts roles and terminal actions", () => {
    expect(allowedOnlineActions(order, "guest")).toEqual({
      next: null,
      collect: false,
      cancel: false,
      refund: false,
    });
    expect(allowedOnlineActions(order, "manager").refund).toBe(true);
    expect(allowedOnlineActions(order, "cashier").refund).toBe(false);
    for (const status of ["cancelled", "expired", "delivered"])
      expect(
        allowedOnlineActions({ ...order, status }, "cashier"),
      ).toMatchObject({ next: null, cancel: false });
  });
});
