import { expect, it } from "vitest";
import {
  requestQuoteTotal,
  requestQuoteLink,
  requestDate,
} from "./requestHelpers";
it("sums quote charges in paisa", () =>
  expect(requestQuoteTotal([{ amount: "0.1" }, { amount: 0.2 }])).toBe(0.3));
it("uses Pakistan dates across UTC midnight", () =>
  expect(requestDate(new Date("2026-12-31T23:00:00Z"))).toBe("2027-01-01"));
it("builds a quote message only for a phone", () => {
  expect(requestQuoteLink(null, "REQ-1", "Shop")).toBeNull();
  expect(
    decodeURIComponent(requestQuoteLink("+923001112233", "REQ-1", "Shop")!),
  ).toContain("REQ-1");
});
