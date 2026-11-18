// Uploads the sample catalogue photos to the LOCAL Supabase storage.
// Run after `npx supabase db reset` (which loads supabase/seed.sql):  npm run seed:photos
// It only talks to a local Supabase (127.0.0.1 / localhost) and refuses anything else.
import { spawnSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const photos = JSON.parse(await readFile(path.join(here, "photos.json"), "utf8"));

const status = spawnSync("npx supabase status -o env", { shell: true, encoding: "utf8" });
if (status.status !== 0) {
  console.error("Local Supabase is not running. Start it with: npx supabase start");
  process.exit(1);
}
const env = Object.fromEntries(
  status.stdout
    .split(/\r?\n/)
    .map((line) => line.match(/^([A-Z_]+)="?(.*?)"?$/))
    .filter(Boolean)
    .map((m) => [m[1], m[2]]),
);
const api = env.API_URL;
const key = env.SERVICE_ROLE_KEY;
if (!api || !key) {
  console.error("Could not read API_URL and SERVICE_ROLE_KEY from `supabase status`.");
  process.exit(1);
}
if (!["127.0.0.1", "localhost"].includes(new URL(api).hostname)) {
  console.error(`Refusing to upload to a non-local Supabase: ${api}`);
  process.exit(1);
}
const headers = { apikey: key, Authorization: `Bearer ${key}` };

const rows = await fetch(`${api}/rest/v1/product_images?select=storage_path`, { headers }).then((r) => {
  if (!r.ok) throw new Error(`Could not list product images (${r.status})`);
  return r.json();
});
if (!rows.length) {
  console.error("No product images in the database. Run `npx supabase db reset` first.");
  process.exit(1);
}

let uploaded = 0;
for (const { storage_path } of rows) {
  const file = storage_path.split("/").pop();
  const source = photos[file];
  if (!source) {
    console.warn(`No photo listed for ${file}; skipped.`);
    continue;
  }
  const image = await fetch(`${source}?auto=format&fm=jpg&fit=max&w=1600&q=80`);
  if (!image.ok) {
    console.warn(`Could not download ${file} (${image.status}); skipped.`);
    continue;
  }
  const body = Buffer.from(await image.arrayBuffer());
  const put = await fetch(`${api}/storage/v1/object/product-images/${storage_path}`, {
    method: "POST",
    headers: { ...headers, "Content-Type": "image/jpeg", "x-upsert": "true" },
    body,
  });
  if (!put.ok) {
    console.warn(`Upload failed for ${file} (${put.status}): ${await put.text()}`);
    continue;
  }
  uploaded += 1;
  console.log(`Uploaded ${file}`);
}
console.log(`Done: ${uploaded} of ${rows.length} photos uploaded.`);
