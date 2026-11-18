import { test } from "node:test";
import assert from "node:assert/strict";
import { posHeaders } from "./headers.mjs";
import { allowedRequest, securityProblems } from "./check.mjs";
import { envValue, posVercelConfig } from "./pos-vercel.mjs";
import { readFileSync } from "node:fs";
test("POS CSP fixes the environment HTTPS and realtime origins", () => {
  const rendered = posHeaders(
    readFileSync("public/_headers", "utf8"),
    "https://staging.example.test",
  );
  assert.ok(
    rendered.includes(
      "connect-src 'self' https://staging.example.test wss://staging.example.test",
    ),
  );
  assert.ok(!rendered.includes("__SUPABASE_"));
  for (const url of [
    "http://example.test",
    "https://x.test/path",
    "https://user:pass@x.test",
  ])
    assert.throws(() => posHeaders("", url));
});
test("POS Vercel config carries the rendered security headers", () => {
  const config = posVercelConfig(
    readFileSync("public/_headers", "utf8"),
    envValue('A=1\nVITE_SUPABASE_URL="https://db.example.test"\n', "VITE_SUPABASE_URL"),
  );
  assert.equal(config.outputDirectory, "dist");
  const headers = new Headers(
    config.headers[0].headers.map(({ key, value }) => [key, value]),
  );
  assert.deepEqual(securityProblems(headers, "https://db.example.test"), []);
  assert.throws(() => envValue("A=1", "VITE_SUPABASE_URL"));
});
test("network checks distinguish local rehearsal and hosted leakage", () => {
  assert.equal(allowedRequest("http://localhost:3000", false), false);
  assert.equal(allowedRequest("http://127.0.0.1:54321", true), true);
  assert.equal(allowedRequest("https://law" + "rencepur.com/a", true), false);
});
test("hosted header checks fail closed", () => {
  assert.ok(
    securityProblems(new Headers(), "https://db.example.test").includes("CSP"),
  );
  assert.ok(
    securityProblems(new Headers(), "https://db.example.test").includes("HSTS"),
  );
});

test("POS bootstrap uses self-hosted scripts compatible with script-src self", () => {
 const html=readFileSync("index.html","utf8");
 for(const match of html.matchAll(/<script([^>]*)>([\s\S]*?)<\/script>/g)) {
   assert.match(match[1], /\bsrc=/);
   assert.equal(match[2].trim(), "");
 }
 assert.ok(readFileSync("public/theme-bootstrap.js","utf8").includes("pos-theme-v1"));
});
