import { describe, expect, it } from "vitest";
import { canOpen, defaultView, navigation, type Role } from "./navigation";
const allowed: Record<Role, string[]> = {
  admin: [
    "dashboard",
    "pos",
    "online",
    "transactions",
    "inventory",
    "bicycles",
    "kids",
    "sports",
    "ebikes",
    "accessories",
    "parts",
    "customers",
    "reports",
    "commissions",
    "discounts",
    "users",
    "settings",
  ],
  manager: [
    "dashboard",
    "pos",
    "online",
    "transactions",
    "inventory",
    "bicycles",
    "kids",
    "sports",
    "ebikes",
    "accessories",
    "parts",
    "customers",
    "reports",
    "commissions",
    "discounts",
    "settings",
  ],
  cashier: ["pos", "online", "commissions"],
};
describe("navigation permissions", () => {
  for (const role of Object.keys(allowed) as Role[])
    for (const view of navigation)
      it(`${role} → ${view.id}`, () =>
        expect(canOpen(role, view.id)).toBe(allowed[role].includes(view.id)));
  it("refuses unknown roles/views", () => {
    expect(canOpen(undefined, "pos")).toBe(false);
    expect(canOpen("admin", "unknown")).toBe(false);
  });
  it("chooses role defaults", () => {
    expect(defaultView("admin")).toBe("dashboard");
    expect(defaultView("manager")).toBe("dashboard");
    expect(defaultView("cashier")).toBe("pos");
  });
});
