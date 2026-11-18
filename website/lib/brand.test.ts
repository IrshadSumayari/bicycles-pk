import { describe, it, expect } from "vitest";
import { brand, storeAddress, storeJsonLd } from "./brand";
describe("store identity", () => {
  it("uses the configured identity and postal address in structured data", () => {
    const data = storeJsonLd("https://shop.example/");
    expect(data.name).toBe(brand.name);
    expect(data.address.streetAddress).toBe(brand.address.line1);
    expect(storeAddress).toContain(brand.address.city);
    expect(data.image).toBe("https://shop.example/brand/bicycles-icon.svg");
  });
  it("does not publish empty contact or social fields", () => {
    const data = storeJsonLd("https://shop.example/");
    expect(data).not.toHaveProperty("telephone");
    expect(data).not.toHaveProperty("email");
    expect(data).not.toHaveProperty("sameAs");
    expect(brand.whatsapp).toBeNull();
  });
});
