import { describe, it, expect } from "vitest";
import {
  courierTrackingPage,
  orderProgress,
  trackingUpdateError,
  normalizedOrderNumber,
} from "../../shared/orderTracking";
describe("shipment tracking", () => {
  it("uses only fixed official courier pages and never accepts arbitrary URLs", () => {
    expect(courierTrackingPage(" PostEx ")?.url).toBe(
      "https://postex.pk/tracking",
    );
    expect(courierTrackingPage("Leopards Courier")?.url).toBe(
      "https://pk.leopardscourier.com/",
    );
    for (const v of [
      "https://evil.test",
      "javascript:alert(1)",
      "PostEx evil",
      "Other",
      null,
    ])
      expect(courierTrackingPage(v)).toBeNull();
  });
  it("shows pickup and delivery as different routes", () => {
    expect(orderProgress("shipped", "delivery").steps[3]).toMatchObject({
      label: "Shipped",
      state: "current",
    });
    expect(orderProgress("ready_for_pickup", "pickup").steps[3]).toMatchObject({
      label: "Ready for pickup",
      state: "current",
    });
    expect(orderProgress("delivered", "pickup").steps[4].label).toBe(
      "Collected",
    );
  });
  it("does not claim completed delivery for cancelled, expired or returned parcels", () => {
    for (const s of ["cancelled", "expired", "returned_to_sender"]) {
      const p = orderProgress(s, "delivery");
      expect(p.stopped).toBe(true);
      expect(p.notice).toBeTruthy();
      expect(p.steps.some((step) => step.state === "complete")).toBe(false);
    }
    expect(orderProgress("pending_payment", "delivery").notice).toContain(
      "payment",
    );
  });
  it("limits lookup to a normalized order number", () => {
    expect(normalizedOrderNumber(" web-000123 ")).toBe("WEB-000123");
    for (const v of [
      "WEB-1",
      "../orders",
      "https://evil.test",
      "WEB-000123?x=1",
      "<script>",
    ])
      expect(normalizedOrderNumber(v)).toBeNull();
  });
  it("requires shipment metadata and a bounded public update", () => {
    const p = {
      courier: "PostEx",
      tracking_no: "CN123",
      kind: "delayed",
      message: "Courier reports a delay.",
    };
    expect(trackingUpdateError(p)).toBeNull();
    for (const bad of [
      { courier: "" },
      { tracking_no: "" },
      { kind: "delivered" },
      { message: "" },
      { message: "x".repeat(501) },
    ])
      expect(trackingUpdateError({ ...p, ...bad })).not.toBeNull();
  });
});
