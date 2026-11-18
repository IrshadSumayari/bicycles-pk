import autocannon from "autocannon";
import { writeFile, mkdir } from "node:fs/promises";
const args = process.argv.slice(2),
  arg = (key, fallback) => {
    const i = args.indexOf(key);
    return i < 0 ? fallback : args[i + 1];
  };
const website = arg("--website", "http://127.0.0.1:3000"),
  api = arg("--api", "http://127.0.0.1:54321"),
  key = arg("--anon-key", process.env.SUPABASE_ANON_KEY);
for (const value of [website, api]) {
  const url = new URL(value);
  if (
    !["127.0.0.1", "localhost"].includes(url.hostname) &&
    !args.includes("--allow-staging")
  )
    throw Error(
      "Use --allow-staging only with explicit permission for a staging load test",
    );
}
if (!key) throw Error("--anon-key or SUPABASE_ANON_KEY is required");
const duration = Number(arg("--seconds", "15"));
if (!Number.isInteger(duration) || duration < 5 || duration > 60)
  throw Error("Duration must be 5–60 seconds");
const cases = [
  { name: "home", url: website },
  { name: "catalog", url: website + "/search" },
  {
    name: "catalog_list",
    url: api + "/rest/v1/rpc/catalog_list",
    method: "POST",
    headers: { apikey: key, "content-type": "application/json" },
    body: JSON.stringify({ p: { limit: 24, sort: "new" } }),
  },
];
const results = [];
for (const test of cases) {
  const warm = await fetch(test.url, {
    method: test.method,
    headers: test.headers,
    body: test.body,
  });
  await warm.arrayBuffer();
  if (!warm.ok) throw Error(test.name + " warm-up HTTP " + warm.status);
  const times = [];
  let failures = 0;
  const result = await new Promise((resolve, reject) => {
    const instance = autocannon(
      { ...test, connections: 50, duration, pipelining: 1 },
      (error, result) => (error ? reject(error) : resolve(result)),
    );
    instance.on("response", (_client, status, _bytes, time) => {
      times.push(time);
      if (status < 200 || status >= 400) failures++;
    });
  });
  times.sort((a, b) => a - b);
  const p95 = times[Math.max(0, Math.ceil(times.length * 0.95) - 1)] ?? null;
  const row = {
    name: test.name,
    connections: 50,
    seconds: duration,
    responses: times.length,
    p95Milliseconds: p95,
    requestsPerSecond: result.requests.average,
    errors: result.errors,
    timeouts: result.timeouts,
    failedStatuses: failures,
    targetMet: p95 !== null && p95 < 800 && !failures && !result.errors,
  };
  results.push(row);
  console.log(JSON.stringify(row));
}
await mkdir("backups/load-test", { recursive: true });
await writeFile(
  "backups/load-test/latest.json",
  JSON.stringify(results, null, 2) + "\n",
);
if (results.some((r) => !r.targetMet)) process.exitCode = 1;
