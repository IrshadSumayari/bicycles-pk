/// <reference types="vitest/config" />
import { defineConfig, loadEnv } from "vite";
import { readFile, writeFile } from "node:fs/promises";
// @ts-expect-error: shared build-only JavaScript helper has no runtime app imports.
import { posHeaders } from "./scripts/deploy/headers.mjs";
import { fileURLToPath, URL } from "node:url";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";

// https://vite.dev/config/
export default defineConfig(({ mode }) => ({
  plugins: [
    react(),
    tailwindcss(),
    {
      name: "pos-security-headers",
      apply: "build",
      async closeBundle() {
        const env = loadEnv(mode, process.cwd(), "VITE_");
        const template = await readFile("public/_headers", "utf8");
        await writeFile(
          "dist/_headers",
          posHeaders(template, env.VITE_SUPABASE_URL),
        );
      },
    },
  ],
  resolve: { alias: { "@": fileURLToPath(new URL("./src", import.meta.url)) } },
  test: {
    include: ["src/**/*.test.{ts,tsx}"],
  },
}));
