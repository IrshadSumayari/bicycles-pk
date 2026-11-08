import { expect, it } from "vitest";
import { readConsent, analyticsId } from "./consent";
it("requires an explicit valid consent choice", () => {
  expect(readConsent("")).toBeNull();
  expect(readConsent("storefront-analytics=bad")).toBeNull();
  expect(readConsent("x=y; storefront-analytics=accepted")).toBe("accepted");
  expect(readConsent("storefront-analytics=rejected")).toBe("rejected");
});
it("has no analytics provider by default and accepts only configured GA4 IDs", () => {
  expect(analyticsId(undefined)).toBeNull();
  expect(analyticsId("<script>")).toBeNull();
  expect(analyticsId("G-ABC123")).toBe("G-ABC123");
});
