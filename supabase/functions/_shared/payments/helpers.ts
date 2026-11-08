import {
  PaymentError,
  type PaymentEvent,
  type PaymentStatus,
} from "./types.ts";

export function object(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value))
    throw new PaymentError(400, "Send a JSON object");
  return value as Record<string, unknown>;
}

export function text(value: unknown, max = 200): string {
  if (typeof value !== "string" || !value.trim() || value.length > max)
    throw new PaymentError(400, "Invalid payment reference");
  return value;
}

// Compare integer paisa, not binary floating point totals. Reject extra precision.
export function paisa(value: unknown): bigint {
  if (typeof value !== "number" && typeof value !== "string")
    throw new PaymentError(400, "Invalid payment amount");
  const match = /^(0|[1-9]\d{0,11})(?:\.(\d{1,2}))?$/.exec(String(value));
  if (!match) throw new PaymentError(400, "Invalid payment amount");
  return BigInt(match[1]) * 100n + BigInt((match[2] ?? "").padEnd(2, "0"));
}
export function amountMatches(actual: unknown, expected: unknown): boolean {
  return paisa(actual) === paisa(expected);
}

// This is the MOCK contract only. No Easypaisa codes are guessed here.
export function mockStatus(code: unknown): PaymentStatus {
  if (code === "paid" || code === "refunded") return code;
  return "failed";
}
export function parseMockEvent(raw: unknown): PaymentEvent {
  const data = object(raw);
  const method = data.method;
  if (method !== "card" && method !== "wallet")
    throw new PaymentError(400, "Invalid payment method");
  paisa(data.amount);
  const orderNo = text(data.orderNo, 50);
  if (!/^WEB-\d{6,}$/.test(orderNo))
    throw new PaymentError(400, "Invalid order number");
  // Keep only known payment fields. Never persist arbitrary headers, credentials
  // or a notification's unexpected card/contact fields as provider raw data.
  const clean: Omit<PaymentEvent, "raw"> = {
    providerRef: text(data.providerRef),
    orderNo,
    amount: Number(data.amount),
    method,
    status: mockStatus(data.status),
  };
  return { ...clean, raw: clean };
}

export function paymentDecision(
  current: string | undefined,
  next: PaymentStatus,
): "apply" | "duplicate" | "ignore" {
  if (current === next) return "duplicate";
  if (current === "refunded" || (current === "paid" && next === "failed"))
    return "ignore";
  return "apply";
}

export async function signBody(
  secret: string,
  rawBody: string,
): Promise<string> {
  const bytes = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    bytes.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signed = await crypto.subtle.sign("HMAC", key, bytes.encode(rawBody));
  return Array.from(new Uint8Array(signed), (n) =>
    n.toString(16).padStart(2, "0"),
  ).join("");
}
export async function verifyBody(
  secret: string,
  rawBody: string,
  signature: string | null,
): Promise<boolean> {
  if (!signature || !/^[a-f0-9]{64}$/i.test(signature)) return false;
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["verify"],
  );
  const bytes = Uint8Array.from(signature.match(/../g) ?? [], (pair) =>
    parseInt(pair, 16),
  );
  return crypto.subtle.verify(
    "HMAC",
    key,
    bytes,
    new TextEncoder().encode(rawBody),
  );
}
