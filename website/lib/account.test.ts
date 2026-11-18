import { describe, it, expect } from "vitest";
import { returnPath, normalizePhone } from "./account";
describe("account helpers", () => {
  it("rejects external return paths", () => {
    expect(returnPath("//evil.test")).toBe("/account");
    expect(returnPath("/account\\evil")).toBe("/account");
    expect(returnPath("/account/orders")).toBe("/account/orders");
    expect(returnPath("/checkout")).toBe("/checkout");
    expect(returnPath("/collections")).toBe("/account");
  });
  it("normalizes Pakistan phone numbers", () =>
    expect(normalizePhone("0300 111 7788")).toBe("+923001117788"));
});
