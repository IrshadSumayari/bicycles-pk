import { readFileSync, writeFileSync } from "node:fs";
import { pathToFileURL } from "node:url";
import { headerLines, posHeaders } from "./headers.mjs";

// Vercel ignores dist/_headers, so the POS project receives the same
// environment-rendered headers through a generated vercel.json.
export function posVercelConfig(template, supabaseUrl) {
  return {
    $schema: "https://openapi.vercel.sh/vercel.json",
    framework: "vite",
    installCommand: "npm ci",
    buildCommand: "npm run build",
    outputDirectory: "dist",
    headers: [
      {
        source: "/(.*)",
        headers: headerLines(posHeaders(template, supabaseUrl)).map(
          ([key, value]) => ({ key, value }),
        ),
      },
    ],
  };
}

// Reads one variable from the dotenv file written by `vercel pull`.
export function envValue(text, name) {
  for (const line of text.split(/\r?\n/)) {
    const match = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)$/);
    if (match?.[1] === name) return match[2].trim().replace(/^(["'])(.*)\1$/, "$2");
  }
  throw new Error(`${name} is not set in the pulled Vercel environment`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const envFile = process.argv[2] ?? ".vercel/.env.production.local";
  const config = posVercelConfig(
    readFileSync("public/_headers", "utf8"),
    envValue(readFileSync(envFile, "utf8"), "VITE_SUPABASE_URL"),
  );
  writeFileSync("vercel.json", JSON.stringify(config, null, 2) + "\n");
}
