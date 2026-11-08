import { afterEach, describe, expect, it, vi } from "vitest";
import { NextRequest } from "next/server";
import { proxy } from "../proxy";
import { ACCESS_COOKIE, accessToken } from "./access-gate";
afterEach(() => vi.unstubAllEnvs());
const site = "https://bicycles.pk";
const post = (body: Record<string, string>) =>
  new NextRequest(site + "/_access", {
    method: "POST",
    body: new URLSearchParams(body),
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
  });
describe("private site access key", () => {
  it("leaves the site open when no key is configured", async () => {
    vi.stubEnv("SITE_ACCESS_KEY", "");
    const r = await proxy(new NextRequest(site + "/collections"));
    expect(r.status).toBe(200);
  });
  it("asks visitors without the key for it", async () => {
    vi.stubEnv("SITE_ACCESS_KEY", "open-sesame");
    const r = await proxy(new NextRequest(site + "/collections?c=bras"));
    expect(r.status).toBe(401);
    expect(r.headers.get("X-Robots-Tag")).toContain("noindex");
    expect(r.headers.get("Content-Security-Policy")).toContain("default-src");
    expect(await r.text()).toContain('value="/collections?c=bras"');
  });
  it("rejects a wrong key", async () => {
    vi.stubEnv("SITE_ACCESS_KEY", "open-sesame");
    const r = await proxy(post({ key: "guess", next: "/" }));
    expect(r.status).toBe(401);
    expect(r.cookies.get(ACCESS_COOKIE)).toBeUndefined();
  });
  it("remembers the right key and returns to the page", async () => {
    vi.stubEnv("SITE_ACCESS_KEY", "open-sesame");
    const r = await proxy(post({ key: "open-sesame", next: "/collections?c=bras" }));
    expect(r.status).toBe(303);
    expect(r.headers.get("location")).toBe(site + "/collections?c=bras");
    expect(r.cookies.get(ACCESS_COOKIE)?.value).toBe(
      await accessToken("open-sesame"),
    );
    expect(r.cookies.get(ACCESS_COOKIE)?.maxAge).toBe(60 * 60 * 24);
  });
  it.each(["//evil.example", "https://evil.example", "/\evil.example"])(
    "never redirects off-site to %s",
    async (next) => {
      vi.stubEnv("SITE_ACCESS_KEY", "open-sesame");
      const r = await proxy(post({ key: "open-sesame", next }));
      expect(new URL(r.headers.get("location")!).origin).toBe(site);
    },
  );
  it("lets visitors with the key through, until the key changes", async () => {
    vi.stubEnv("SITE_ACCESS_KEY", "open-sesame");
    const req = () =>
      new NextRequest(site + "/collections", {
        headers: { cookie: `${ACCESS_COOKIE}=${token}` },
      });
    const token = await accessToken("open-sesame");
    expect((await proxy(req())).status).toBe(200);
    vi.stubEnv("SITE_ACCESS_KEY", "new-key");
    expect((await proxy(req())).status).toBe(401);
  });
});
