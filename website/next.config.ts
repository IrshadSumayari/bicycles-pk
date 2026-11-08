import type { NextConfig } from "next";
import path from "node:path";
import redirects from "./redirects.json";
import { buildCsp, securityHeaders } from "./lib/security";
const storage = new URL(
  process.env.NEXT_PUBLIC_SUPABASE_URL || "https://example.supabase.co",
);
const config: NextConfig = {
  turbopack: { root: path.resolve(import.meta.dirname, "..") },
  poweredByHeader: false,
  async redirects() {
    return redirects;
  },
  async headers() {
    return [
      {
        source: "/:path*",
        headers: [
          ...securityHeaders(process.env.NODE_ENV === "production"),
          {
            key: "Content-Security-Policy",
            value: buildCsp({
              supabase: storage.origin,
              development: process.env.NODE_ENV === "development",
              payments: process.env.PAYMENT_CHECKOUT_ORIGINS,
              analyticsId: process.env.NEXT_PUBLIC_ANALYTICS_ID,
            }),
          },
        ],
      },
    ];
  },
  images: {
    remotePatterns: [
      {
        protocol: storage.protocol === "http:" ? "http" : "https",
        hostname: storage.hostname,
        port: storage.port,
        pathname: "/storage/v1/object/public/product-images/**",
        search: "",
      },
    ],
    // Local development only; the allow-list still fixes the exact host/path.
    dangerouslyAllowLocalIP: ["localhost", "127.0.0.1", "[::1]"].includes(
      storage.hostname,
    ),
    maximumRedirects: 0,
  },
};
export default config;
