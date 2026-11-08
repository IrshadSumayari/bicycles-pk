type PolicyOptions = {
  nonce?: string;
  supabase: string;
  development?: boolean;
  payments?: string;
  analyticsId?: string;
};
export function paymentOrigins(value = ""): string[] {
  return [
    ...new Set(
      value
        .split(",")
        .map((v) => v.trim())
        .filter(Boolean)
        .map((value) => {
          const url = new URL(value);
          if (
            url.protocol !== "https:" ||
            url.username ||
            url.password ||
            url.pathname !== "/" ||
            url.search ||
            url.hash
          )
            throw new Error(
              "Payment checkout origins must be exact HTTPS provider origins",
            );
          return url.origin;
        }),
    ),
  ];
}
export function buildCsp({
  nonce,
  supabase,
  development = false,
  payments = "",
  analyticsId = "",
}: PolicyOptions) {
  const origin = new URL(supabase).origin,
    ws = origin.replace(/^http/, "ws"),
    providers = paymentOrigins(payments),
    analytics = /^G-[A-Z0-9]+$/.test(analyticsId);
  return [
    "default-src 'self'",
    `script-src 'self'${nonce ? ` 'nonce-${nonce}' 'strict-dynamic'` : ""}${development ? " 'unsafe-eval'" : ""}${analytics ? " https://www.googletagmanager.com" : ""}`,
    "style-src 'self' 'unsafe-inline'",
    `img-src 'self' data: blob: ${origin}${analytics ? " https://www.google-analytics.com https://region1.google-analytics.com" : ""}`,
    // blob: lets the 3D viewer read textures packed inside a .glb model.
    `connect-src 'self' blob: ${origin} ${ws}${development ? " ws://localhost:* ws://127.0.0.1:*" : ""}${analytics ? " https://www.google-analytics.com https://region1.google-analytics.com https://www.googletagmanager.com" : ""}`,
    "font-src 'self'",
    "object-src 'none'",
    "base-uri 'self'",
    "frame-ancestors 'none'",
    `form-action 'self'${providers.length ? " " + providers.join(" ") : ""}`,
    "frame-src 'none'",
  ].join("; ");
}
export function securityHeaders(production: boolean) {
  return [
    { key: "X-Frame-Options", value: "DENY" },
    { key: "X-Content-Type-Options", value: "nosniff" },
    { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
    {
      key: "Permissions-Policy",
      value: "camera=(), microphone=(), geolocation=(), payment=()",
    },
    ...(production
      ? [
          {
            key: "Strict-Transport-Security",
            value: "max-age=31536000; includeSubDomains",
          },
        ]
      : []),
  ];
}
