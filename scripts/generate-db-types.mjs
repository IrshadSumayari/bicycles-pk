import { spawnSync } from "node:child_process";
import { writeFile } from "node:fs/promises";
import { format } from "prettier";
// Buffer CLI output so its Windows file handle closes before formatting/writing.
const result = spawnSync(
  "supabase gen types typescript --local --schema public",
  { shell: true, encoding: "utf8", maxBuffer: 10 * 1024 * 1024 },
);
if (result.stderr) process.stderr.write(result.stderr);
if (result.status !== 0) process.exit(result.status ?? 1);
await writeFile(
  "src/lib/database.types.ts",
  await format(result.stdout, { parser: "typescript" }),
);
