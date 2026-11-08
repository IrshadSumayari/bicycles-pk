import { describe, it, expect } from "vitest";
import {
  countdown,
  validateCheckout,
  paymentOptions,
  type CheckoutForm,
} from "./checkout";
const form: CheckoutForm = {
  contact_name: "Customer",
  phone: "03001234567",
  email: "",
  fulfilment: "pickup",
  address: { line1: "", line2: "", city: "", postal_code: "" },
  payment_method: "card",
  notes_customer: "",
};
describe("checkout validation", () => {
  it("accepts pickup and delivery with valid contact", () => {
    expect(
      validateCheckout(form, true, ["card", "easypaisa", "cod"]),
    ).toBeNull();
    expect(
      validateCheckout(
        {
          ...form,
          fulfilment: "delivery",
          address: { ...form.address, line1: "12 Road", city: "Lahore" },
        },
        true,
        ["card", "easypaisa", "cod"],
      ),
    ).toBeNull();
  });
  it("rejects missing contact, invalid phone and email", () => {
    expect(validateCheckout({ ...form, contact_name: "" }, true)).toBeTruthy();
    expect(validateCheckout({ ...form, phone: "123" }, true)).toBeTruthy();
    expect(validateCheckout({ ...form, email: "bad" }, true)).toBeTruthy();
  });
  it("requires delivery address and enforces COD eligibility", () => {
    expect(
      validateCheckout({ ...form, fulfilment: "delivery" }, true),
    ).toBeTruthy();
    expect(
      validateCheckout({ ...form, payment_method: "cod" }, false),
    ).toBeTruthy();
  });
});
describe("hold countdown", () => {
  it("formats minutes, seconds, rounding and expiration", () => {
    expect(
      countdown("2026-10-20T00:02:05Z", Date.parse("2026-10-20T00:00:00Z")),
    ).toBe("2:05");
    expect(
      countdown("2026-10-20T00:00:00.500Z", Date.parse("2026-10-20T00:00:00Z")),
    ).toBe("0:01");
    expect(countdown("2026-10-19", Date.parse("2026-10-20"))).toBe("Expired");
    expect(countdown("bad", 0)).toBe("Expired");
    expect(countdown(null, 0)).toBe("No payment hold");
  });
});

describe("COD-only launch methods", () => {
  it("fails closed until a quote arrives", () =>
    expect(paymentOptions()).toEqual([]));
  it("shows only COD when card is disabled", () => {
    expect(paymentOptions({ payment_methods: ["cod"] })).toEqual([
      ["cod", "Cash on delivery"],
    ]);
    expect(
      validateCheckout({ ...form, payment_method: "cod" }, true, ["cod"]),
    ).toBeNull();
    expect(validateCheckout(form, true, ["cod"])).toBe(
      "Choose an available payment method",
    );
  });
  it("shows enabled methods and ignores unknown server values", () => {
    expect(
      paymentOptions({
        payment_methods: ["card", "easypaisa", "cod", "other"],
      }),
    ).toHaveLength(3);
    expect(paymentOptions({ payment_methods: [] })).toEqual([]);
  });
});
