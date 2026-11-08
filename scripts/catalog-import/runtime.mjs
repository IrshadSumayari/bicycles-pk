import { createClient } from "@supabase/supabase-js";
import { createInterface } from "node:readline/promises";
import { Writable } from "node:stream";
import { readFile, mkdir, writeFile, rename } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
export const root = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../..",
);
export const backups = path.join(root, "backups/catalog-import");
export const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
export function options(argv = process.argv.slice(2)) {
  const o = {
    apply: false,
    source: "D:/LadyVogue/storefront/src/data",
    limit: Infinity,
  };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--apply") o.apply = true;
    else if (arg === "--dry-run") o.dry = true;
    else if (arg === "--images") throw Error("Upload approved photos through the POS image manager; automatic source image imports are disabled");
    else if (["--url", "--anon-key", "--source", "--limit"].includes(arg)) {
      if (!argv[i + 1] || argv[i + 1].startsWith("--"))
        throw Error("Missing value for " + arg);
      o[arg.slice(2)] = argv[++i];
    } else throw Error("Unknown option " + arg);
  }
  o.limit = Number(o.limit);
  if (!(o.limit > 0) || (!Number.isInteger(o.limit) && o.limit !== Infinity))
    throw Error("Limit must be a positive whole number");
  if (o.apply && o.dry) throw Error("Choose --dry-run or --apply");
  if (!o.url || !o["anon-key"])
    throw Error("--url and --anon-key are required (public project key only)");
  const url = new URL(o.url);
  if (
    url.protocol !== "https:" &&
    !(
      url.protocol === "http:" &&
      ["localhost", "127.0.0.1"].includes(url.hostname)
    )
  )
    throw Error("Use HTTPS, or local Supabase");
  let role;
  try {
    role = JSON.parse(
      Buffer.from(o["anon-key"].split(".")[1], "base64url"),
    ).role;
  } catch {
    /* Publishable keys are not JWTs. */
  }
  if (role === "service_role" || o["anon-key"].startsWith("sb_secret_"))
    throw Error("Service-role/secret keys are forbidden");
  return o;
}
export async function login(o) {
  let muted = false;
  const output = new Writable({
    write(chunk, _encoding, done) {
      if (!muted) process.stdout.write(chunk);
      done();
    },
  });
  const rl = createInterface({
    input: process.stdin,
    output,
    terminal: !!process.stdin.isTTY,
  });
  let email, password;
  try {
    email = await rl.question("Admin email: ");
    process.stdout.write("Admin password: ");
    muted = !!process.stdin.isTTY;
    password = await rl.question("");
    process.stdout.write("\n");
  } finally {
    rl.close();
  }
  const client = createClient(o.url, o["anon-key"], {
    auth: {
      persistSession: false,
      autoRefreshToken: true,
      detectSessionInUrl: false,
    },
  });
  const signed = await client.auth.signInWithPassword({
    email: email.trim(),
    password,
  });
  password = undefined;
  if (signed.error)
    throw Error("Admin sign-in failed: " + signed.error.message);
  const profile = await client
    .from("users")
    .select("role,active")
    .eq("id", signed.data.user.id)
    .single();
  if (profile.error || profile.data?.role !== "admin" || !profile.data.active) {
    await client.auth.signOut();
    throw Error("Use an active ADMIN account");
  }
  return client;
}
export async function pages(client, table, columns) {
  let rows = [];
  for (let offset = 0; ; offset += 1000) {
    const r = await client
      .from(table)
      .select(columns)
      .range(offset, offset + 999);
    if (r.error) throw r.error;
    rows.push(...r.data);
    if (r.data.length < 1000) return rows;
  }
}
export async function retry(action) {
  for (let attempt = 0; ; attempt++) {
    try {
      return await action();
    } catch (e) {
      if (
        attempt >= 3 ||
        (!e.retryable && e.name !== "TypeError" && e.name !== "TimeoutError")
      )
        throw e;
      await delay(500 * 2 ** attempt);
    }
  }
}
export async function rpc(client, name, args) {
  return retry(async () => {
    const r = await client
      .rpc(name, args)
      .abortSignal(AbortSignal.timeout(20000));
    if (r.error) {
      r.error.retryable = r.status === 429 || r.status >= 500;
      throw r.error;
    }
    return r.data;
  });
}
export async function jsonFile(file, fallback = {}) {
  try {
    return JSON.parse(await readFile(file, "utf8"));
  } catch (e) {
    if (e.code === "ENOENT") return fallback;
    throw e;
  }
}
export async function saveJson(file, value) {
  await mkdir(path.dirname(file), { recursive: true });
  const temporary = file + ".tmp";
  await writeFile(temporary, JSON.stringify(value, null, 2) + "\n");
  await rename(temporary, file);
}
const cell = (v) => {
  let s = String(v ?? "");
  if (/^[=+@-]/.test(s)) s = "'" + s;
  return '"' + s.replaceAll('"', '""') + '"';
};
export async function report(rows, label) {
  await mkdir(backups, { recursive: true });
  const file = path.join(
    backups,
    label + "-" + new Date().toISOString().replace(/[:.]/g, "-") + ".csv",
  );
  await writeFile(
    file,
    String.fromCharCode(0xfeff) +
      [
        "code,handle,variants,status,problem",
        ...rows.map((r) =>
          [r.code, r.handle, r.variants, r.status, r.problem]
            .map(cell)
            .join(","),
        ),
      ].join("\r\n"),
  );
  return file;
}
