import { expect, it } from "vitest";
import { buildCsp, paymentOrigins, securityHeaders } from "./security";
it("limits scripts with a nonce and excludes the old storefront origin", () => {
  const csp = buildCsp({
    nonce: "unique",
    supabase: "https://project.supabase.co",
  });
  expect(csp).toContain("'nonce-unique'");
  expect(csp).toContain("frame-ancestors 'none'");
  expect(csp.split("; ").find((v) => v.startsWith("script-src"))).not.toContain(
    "unsafe-inline",
  );
  expect(csp).not.toContain("example.com");
  expect(csp).not.toContain("googletagmanager");
});
it("permits only configured HTTPS payment origins and optional analytics", () => {
  expect(
    paymentOrigins("https://checkout.example,https://checkout.example"),
  ).toEqual(["https://checkout.example"]);
  expect(() => paymentOrigins("http://bad.example")).toThrow();
  expect(() => paymentOrigins("https://checkout.example/path")).toThrow();
  expect(() =>
    paymentOrigins("https://user:password@checkout.example"),
  ).toThrow();
  expect(
    buildCsp({
      supabase: "http://127.0.0.1:54321",
      payments: "https://checkout.example",
      analyticsId: "G-ABC123",
    }),
  ).toContain("form-action 'self' https://checkout.example");
});
it("HSTS is enabled only in production", () => {
  expect(
    securityHeaders(false).some((h) => h.key === "Strict-Transport-Security"),
  ).toBe(false);
  expect(
    securityHeaders(true).some((h) => h.key === "Strict-Transport-Security"),
  ).toBe(true);
});
