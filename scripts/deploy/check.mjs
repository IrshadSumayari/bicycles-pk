import { readFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";
import { chromium } from "@playwright/test";
import { headerLines } from "./headers.mjs";
export const localHost = (value) =>
  ["localhost", "127.0.0.1", "[::1]"].includes(new URL(value).hostname);
export function allowedRequest(value, local) {
  const url = new URL(value);
  return (
    !/(^|\.)law(?:rence)pur\.com$/i.test(url.hostname) &&
    (local || !localHost(value))
  );
}
export function securityProblems(headers, supabase, { local = false } = {}) {
  const get = (key) => headers.get(key) ?? "";
  const csp = get("content-security-policy");
  const checks = {
    CSP:
      csp.includes("default-src 'self'") &&
      csp.includes(new URL(supabase).origin) &&
      csp.includes(new URL(supabase).origin.replace(/^http/, "ws")) &&
      csp.includes("frame-ancestors 'none'"),
    nosniff: get("x-content-type-options").toLowerCase() === "nosniff",
    referrer: get("referrer-policy") === "strict-origin-when-cross-origin",
    permissions: ["camera=()", "microphone=()", "geolocation=()"].every((x) =>
      get("permissions-policy").includes(x),
    ),
    HSTS: local || /max-age=[1-9]\d*/.test(get("strict-transport-security")),
  };
  return Object.entries(checks)
    .filter(([, ok]) => !ok)
    .map(([name]) => name);
}
export async function runChecks({
  website,
  pos,
  supabase,
  anonKey,
  local = false,
}) {
  const targets = [website, pos, supabase];
  if (local && !targets.every(localHost))
    throw new Error("--local requires all three loopback URLs");
  if (
    !local &&
    targets.some((x) => new URL(x).protocol !== "https:" || localHost(x))
  )
    throw new Error("Hosted targets must use HTTPS and no localhost");
  let failures = 0;
  const check = async (name, fn) => {
    try {
      const note = await fn();
      console.log(`PASS ${name}${note ? " : " + note : ""}`);
    } catch {
      failures++;
      console.log(`FAIL ${name}`);
    }
  };
  const request = async (url, options = {}) =>
    fetch(url, { ...options, signal: AbortSignal.timeout(15000) });
  const rpc = async (name, p) =>
    request(new URL("/rest/v1/rpc/" + name, supabase), {
      method: "POST",
      headers: {
        apikey: anonKey,
        Authorization: "Bearer " + anonKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(p),
    });
  for (const [name, url] of [
    ["Website", website],
    ["POS", pos],
  ]) {
    await check(
      name + " loads" + (local ? " locally" : " over HTTPS"),
      async () => {
        const r = await request(url);
        if (!r.ok) throw Error();
        if (!local && new URL(r.url).protocol !== "https:") throw Error();
      },
    );
    await check(name + " security headers", async () => {
      // Vite dev does not apply the hosted response headers. Validate the
      // exact environment-rendered build artifact locally; hosted checks use HTTP.
      let headers;
      if (local && name === "POS") {
        const text = await readFile("dist/_headers", "utf8");
        if (text.includes("__SUPABASE_")) throw Error();
        headers = new Headers(headerLines(text));
      } else headers = (await request(url)).headers;
      if (securityProblems(headers, supabase, { local }).length) throw Error();
      return local && name === "POS"
        ? "validated dist/_headers; verify HTTP headers after Vercel deploy"
        : "";
    });
  }
  if (local) console.log("SKIP www redirect : no local www DNS/TLS");
  else
    await check("www redirects to apex", async () => {
      const apex = new URL(website);
      apex.hostname = apex.hostname.replace(/^staging\./, "");
      apex.pathname = "/";
      const www = new URL(apex);
      www.hostname = "www." + apex.hostname;
      const r = await request(www, { redirect: "manual" });
      const location = r.headers.get("location");
      if (
        ![301, 302, 307, 308].includes(r.status) ||
        !location ||
        new URL(location, www).origin !== apex.origin
      )
        throw Error();
    });
  let row;
  await check("catalog RPC answers", async () => {
    const r = await rpc("catalog_list", { p: { page: 1, limit: 1 } });
    if (!r.ok) throw Error();
    const data = await r.json();
    row = (
      Array.isArray(data)
        ? data
        : (data.items ?? data.products ?? data.rows ?? [])
    )[0];
  });
  await check("anonymous staff functions refused", async () => {
    for (const [name, p] of [
      ["list_online_orders", { p: {} }],
      ["update_settings", { p: {} }],
    ]) {
      const r = await rpc(name, p);
      const b = await r.json();
      if (r.ok || b.code !== "42501") throw Error();
    }
  });
  await check("payment-create refuses missing JWT", async () => {
    const r = await request(new URL("/functions/v1/payment-create", supabase), {
      method: "POST",
      headers: { apikey: anonKey, "Content-Type": "application/json" },
      body: JSON.stringify({ orderNo: "WEB-000001", method: "card" }),
    });
    if (![401, 403].includes(r.status)) throw Error();
  });
  await check("quote offers COD only", async () => {
    // catalog_list rows represent styles; catalog_product supplies variant IDs.
    if (!row?.slug) throw Error();
    const pr = await rpc("catalog_product", { p_slug: row.slug });
    if (!pr.ok) throw Error();
    const product = await pr.json();
    const variant = product.variants?.[0];
    if (!variant?.variant_id) throw Error();
    const r = await rpc("quote_online_order", {
      p: {
        fulfilment: "pickup",
        lines: [{ variant_id: variant.variant_id, quantity: 1 }],
      },
    });
    const quote = await r.json();
    if (
      !r.ok ||
      JSON.stringify(quote.payment_methods) !== '["cod"]' ||
      !quote.cod_allowed
    )
      throw Error();
  });
  const browser = await chromium.launch({ headless: true });
  try {
    for (const [name, url] of [
      ["Website", website],
      ["POS", pos],
    ])
      await check(
        name + " browser / network" + (name === "POS" ? " / sign-in" : ""),
        async () => {
          const page = await browser.newPage();
          const bad = [];
          const errors = [];
          page.on("request", (r) => {
            if (!allowedRequest(r.url(), local)) bad.push(true);
          });
          page.on("pageerror", () => errors.push(true));
          page.on("console", message => {
            if (message.type() === "error" && /Content Security Policy|violates.+directive|Refused to (load|execute)/i.test(message.text())) errors.push(true);
          });
          try {
            await page.goto(url, { waitUntil: "networkidle", timeout: 30000 });
            if (
              name === "POS" &&
              !/sign in|create account|set up/i.test(
                await page.locator("body").innerText(),
              )
            )
              throw Error();
            if (name === "Website")
              for (const path of ["/cart", "/checkout"])
                await page.goto(new URL(path, url).href, {
                  waitUntil: "networkidle",
                  timeout: 30000,
                });
            if (bad.length || errors.length) throw Error();
          } finally {
            await page.close();
          }
        },
      );
  } finally {
    await browser.close();
  }
  return failures;
}
if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(process.argv[1]).href
) {
  const args = process.argv.slice(2);
  const options = {};
  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--local") options.local = true;
    else if (
      ["--website", "--pos", "--supabase", "--anon-key"].includes(args[i])
    ) {
      const key = { "--anon-key": "anonKey" }[args[i]] ?? args[i].slice(2);
      options[key] = args[++i];
    } else throw Error("Unknown argument");
  }
  options.anonKey ??= process.env.SUPABASE_ANON_KEY;
  if (!options.website || !options.pos || !options.supabase || !options.anonKey)
    throw Error(
      "Provide --website --pos --supabase and public --anon-key (or SUPABASE_ANON_KEY environment variable)",
    );
  process.exitCode = (await runChecks(options)) ? 1 : 0;
}
