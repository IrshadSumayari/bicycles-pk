import { afterEach, describe, expect, it, vi } from "vitest";
import { NextRequest } from "next/server";
import { proxy } from "../proxy";
afterEach(() => vi.unstubAllEnvs());
describe("unconfigured storefront authentication", () => {
  const unconfigure = () => {
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "");
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY", "");
  };
  it("keeps sign-in available without exposing protected routes", async () => {
    unconfigure();
    const r = await proxy(
      new NextRequest("https://bicycles.pk/account/sign-in"),
    );
    expect(r.status).toBe(200);
    expect(r.headers.get("Cache-Control")).toBe("private, no-store");
    expect(r.headers.get("Content-Security-Policy")).toContain("default-src");
  });
  it.each(["/account", "/account/orders", "/checkout?from=bag"])(
    "redirects %s to sign-in with a return path",
    async (path) => {
      unconfigure();
      const r = await proxy(new NextRequest("https://bicycles.pk" + path));
      expect(r.status).toBe(307);
      const url = new URL(r.headers.get("location")!);
      expect(url.pathname).toBe("/account/sign-in");
      expect(url.searchParams.get("next")).toBe(path);
      expect(r.headers.get("Cache-Control")).toBe("private, no-store");
    },
  );
  it("continues to serve the public catalog", async () => {
    unconfigure();
    const r = await proxy(new NextRequest("https://bicycles.pk/collections"));
    expect(r.status).toBe(200);
    expect(r.headers.get("location")).toBeNull();
  });
});
