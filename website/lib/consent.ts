export type Consent = "accepted" | "rejected" | null;
export function readConsent(cookie: string): Consent {
  const value = cookie
    .split(";")
    .map((p) => p.trim())
    .find((p) => p.startsWith("storefront-analytics="))
    ?.split("=")[1];
  return value === "accepted" || value === "rejected" ? value : null;
}
export function analyticsId(value: string | undefined): string | null {
  return value && /^G-[A-Z0-9]+$/.test(value) ? value : null;
}
