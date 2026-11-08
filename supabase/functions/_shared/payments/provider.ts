import { EasypaisaProvider } from "./easypaisa.ts";
import { MockProvider } from "./mock.ts";
import { PaymentError, type PaymentProvider } from "./types.ts";

export function assertPaymentEnvironment(
  env: (key: string) => string | undefined,
) {
  if (env("PAYMENT_PROVIDER") !== "mock") return;
  let local = false;
  try {
    const url = new URL(env("SITE_URL") ?? "");
    local =
      ["http:", "https:"].includes(url.protocol) &&
      ["localhost", "127.0.0.1"].includes(url.hostname) &&
      !url.username &&
      !url.password;
  } catch {
    /* Invalid or missing addresses fail closed. */
  }
  if (!local)
    throw new PaymentError(503, "Mock payments are restricted to localhost");
}

export function getProvider(
  env: (key: string) => string | undefined,
): PaymentProvider {
  assertPaymentEnvironment(env);
  const name = env("PAYMENT_PROVIDER");
  if (name === "mock")
    return new MockProvider(env("PAYMENT_WEBHOOK_SECRET") ?? "");
  if (name === "easypaisa") return new EasypaisaProvider();
  throw new PaymentError(503, "Payment provider is not configured");
}
