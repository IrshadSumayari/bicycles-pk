"use client";
import { formatPrice } from "@/lib/helpers";
import { CheckoutSteps } from "./shop-heading";
import { Button } from "./ui/button";
import { Input } from "./ui/input";
import { Textarea } from "./ui/textarea";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import { useStore } from "./store-provider";
import { QuoteTotals, useBagQuote } from "./cart-quote";
import {
  CITIES,
  paymentOptions,
  validateCheckout,
  type CheckoutForm as Form,
} from "@/lib/checkout";
import { ordersService } from "@/lib/orders";
import type { CartLine } from "@/lib/cart";
import { getErrorMessage } from "@/lib/errors";
type Attempt = {
  request_id: string;
  form: Form;
  lines: CartLine[];
  orderNo?: string;
};
export function Checkout({
  accountId,
  name,
  phone,
  email,
}: {
  accountId: string;
  name: string;
  phone: string;
  email: string;
}) {
  const router = useRouter();
  const { lines, ready, dispatch } = useStore();
  const [form, setForm] = useState<Form>({
    contact_name: name,
    phone,
    email,
    fulfilment: "pickup",
    address: { line1: "", line2: "", city: "", postal_code: "" },
    payment_method: "cod",
    notes_customer: "",
  });
  const [attempt, setAttempt] = useState<Attempt | null>(null);
  const [loaded, setLoaded] = useState(false);
  const [busy, setBusy] = useState(false),
    [error, setError] = useState("");
  const submitting = useRef(false);
  const key = `checkout-attempt-v1:${accountId}`;
  const result = useBagQuote(lines, form.fulfilment);
  const options = paymentOptions(result.quote);
  const selectedMethod =
    options.find(([method]) => method === form.payment_method)?.[0] ??
    options[0]?.[0];
  useEffect(() => {
    const timer = setTimeout(() => {
      try {
        const saved: Attempt | null = JSON.parse(
          sessionStorage.getItem(key) ?? "null",
        );
        if (saved?.request_id && saved.form && Array.isArray(saved.lines)) {
          setAttempt(saved);
          setForm(saved.form);
        }
      } catch {
        /* A new attempt can be made when no valid saved attempt exists. */
      }
      setLoaded(true);
    }, 0);
    return () => clearTimeout(timer);
  }, [key]);
  const save = (value: Attempt) => {
    sessionStorage.setItem(key, JSON.stringify(value));
    setAttempt(value);
  };
  async function submit(event?: React.FormEvent) {
    event?.preventDefault();
    if (submitting.current) return;
    submitting.current = true;
    setBusy(true);
    setError("");
    try {
      let current = attempt;
      if (!current) {
        if (
          !result.quote ||
          result.loading ||
          Object.keys(result.unavailable).length ||
          !lines.length
        )
          throw new Error("Review your bag and remove unavailable items");
        const checkoutForm = {
          ...form,
          payment_method: selectedMethod ?? form.payment_method,
        };
        const validation = validateCheckout(
          checkoutForm,
          result.quote.cod_allowed,
          result.quote.payment_methods,
        );
        if (validation) throw new Error(validation);
        current = {
          request_id: crypto.randomUUID(),
          form: checkoutForm,
          lines,
        };
        // Persist BEFORE sending. An uncertain network result always retries the
        // same intent, even after reload; it must not create a second order.
        save(current);
      }
      if (!current.orderNo) {
        const order = await ordersService.create(
          current.form,
          current.lines,
          current.request_id,
        );
        current = { ...current, orderNo: order.order_no };
        save(current);
        dispatch({ type: "clear" });
      }
      if (current.form.payment_method === "cod") {
        sessionStorage.removeItem(key);
        router.push(`/account/orders/${current.orderNo}?created=1`);
      } else
        await ordersService.payment(
          current.orderNo!,
          current.form.payment_method,
        );
    } catch (error) {
      // A database validation error rolls back the entire create operation.
      // Network failures remain saved because their outcome is uncertain.
      if (
        error &&
        typeof error === "object" &&
        "code" in error &&
        error.code === "P0001" &&
        !attempt?.orderNo
      ) {
        sessionStorage.removeItem(key);
        setAttempt(null);
      }
      setError(getErrorMessage(error));
    } finally {
      submitting.current = false;
      setBusy(false);
    }
  }
  if (!loaded || !ready) return <p role="status">Loading checkout…</p>;
  if (attempt?.orderNo)
    return (
      <section className="section space-y-5">
        <h1 className="text-3xl">Order {attempt.orderNo} created</h1>
        <p>Your items are reserved while payment is pending.</p>
        {error && <p role="alert">{error}</p>}
        <Button className="" disabled={busy} onClick={() => void submit()}>
          {busy ? "Please wait…" : "Continue to payment"}
        </Button>
        <Link
          className="block underline"
          href={`/account/orders/${attempt.orderNo}`}
        >
          View order and payment status
        </Link>
        <Button
          className="underline"
          onClick={() => {
            sessionStorage.removeItem(key);
            setAttempt(null);
          }}
        >
          Start a new checkout
        </Button>
      </section>
    );
  if (!lines.length && !attempt)
    return (
      <section className="section">
        <h1 className="text-3xl mb-5">Your bag is empty</h1>
        <Link href="/search">Explore the collection</Link>
      </section>
    );
  const field = (
    label: string,
    name: "contact_name" | "phone" | "email",
    type = "text",
  ) => (
    <label className="block">
      {label}
      <Input
        className="field"
        type={type}
        required={name !== "email"}
        autoComplete={
          name === "contact_name" ? "name" : name === "phone" ? "tel" : "email"
        }
        value={form[name]}
        onChange={(e) => setForm((f) => ({ ...f, [name]: e.target.value }))}
      />
    </label>
  );
  return (
    <section className="section checkout-page">
      <p className="lv-eyebrow">ALMOST YOURS</p>
      <h1 className="lv-checkout-title">The finishing touches.</h1>
      <p className="lv-checkout-intro">
        Confirm your details and review your order.
      </p>
      <CheckoutSteps current="checkout" />
      <details className="lv-checkout-overview">
        <summary>
          <span>
            Your order <small>View details</small>
          </span>
          <strong>
            {result.loading
              ? "Updating…"
              : result.quote
                ? formatPrice(result.quote.total)
                : "Unavailable"}
          </strong>
        </summary>
        {result.error && <p role="alert">{result.error}</p>}
        {result.quote && (
          <>
            <ul className="lv-checkout-items">
              {result.quote.lines.map((line) => (
                <li key={line.variant_id}>
                  <div>
                    <strong>{line.description}</strong>
                    <span>
                      {[line.size, line.color].filter(Boolean).join(" · ")} ·
                      Qty {line.quantity}
                    </span>
                  </div>
                  <b>{formatPrice(line.total)}</b>
                </li>
              ))}
            </ul>
            <QuoteTotals quote={result.quote} />
          </>
        )}
        <Link href="/cart">Edit shopping bag</Link>
      </details>
      <form onSubmit={submit} className="checkout-layout">
        <div className="checkout-form space-y-6">
          {attempt && (
            <p role="status">
              Your previous checkout is saved. Retry it to confirm whether your
              order was created. Contact the shop if you need to change it.
            </p>
          )}
          <fieldset disabled={busy || !!attempt} className="space-y-5">
            <legend className="text-2xl mb-4">
              <span className="lv-form-number">01</span> Contact & delivery
            </legend>
            <p className="lv-required-note">
              All fields are required unless marked optional.
            </p>
            {field("Full name", "contact_name")}
            {field("Phone", "phone", "tel")}
            {field("Email (optional)", "email", "email")}
            <label className="block">
              How would you like your order?
              <select
                className="field"
                value={form.fulfilment}
                onChange={(e) =>
                  setForm((f) => ({
                    ...f,
                    fulfilment: e.target.value as Form["fulfilment"],
                  }))
                }
              >
                <option value="pickup">Store pickup</option>
                <option value="delivery">Courier delivery</option>
              </select>
            </label>
            {form.fulfilment === "delivery" && (
              <div className="space-y-4">
                {(["line1", "line2", "city", "postal_code"] as const).map(
                  (name) => (
                    <label key={name} className="block">
                      {
                        {
                          line1: "Address",
                          line2: "Address line 2 (optional)",
                          city: "City",
                          postal_code: "Postal code (optional)",
                        }[name]
                      }
                      <Input
                        className="field"
                        required={name === "line1" || name === "city"}
                        autoComplete={
                          {
                            line1: "shipping address-line1",
                            line2: "shipping address-line2",
                            city: "shipping address-level2",
                            postal_code: "shipping postal-code",
                          }[name]
                        }
                        maxLength={
                          name === "postal_code"
                            ? 20
                            : name === "city"
                              ? 100
                              : 300
                        }
                        list={name === "city" ? "delivery-cities" : undefined}
                        value={form.address[name]}
                        onChange={(e) =>
                          setForm((f) => ({
                            ...f,
                            address: { ...f.address, [name]: e.target.value },
                          }))
                        }
                      />
                    </label>
                  ),
                )}
                <datalist id="delivery-cities">
                  {CITIES.map((city) => (
                    <option key={city} value={city} />
                  ))}
                </datalist>
              </div>
            )}
            <label className="block">
              Order notes (optional)
              <Textarea
                className="field"
                maxLength={2000}
                value={form.notes_customer}
                onChange={(e) =>
                  setForm((f) => ({ ...f, notes_customer: e.target.value }))
                }
              />
            </label>
          </fieldset>
          <fieldset disabled={busy || !!attempt} className="space-y-4">
            <legend className="text-2xl mb-4">
              <span className="lv-form-number">02</span> Payment method
            </legend>
            {options.map(([value, label]) => (
              <label
                key={value}
                className="lv-payment-choice flex gap-3 items-center border p-4"
              >
                <input
                  type="radio"
                  name="payment_method"
                  value={value}
                  checked={selectedMethod === value}
                  onChange={() =>
                    setForm((f) => ({ ...f, payment_method: value }))
                  }
                />
                {label}
                {value === "card" && (
                  <span
                    className="ml-auto flex gap-2 text-xs"
                    aria-label="Visa and Mastercard"
                  >
                    <span className="font-bold italic text-blue-900">VISA</span>
                    <svg
                      width="36"
                      height="24"
                      viewBox="0 0 36 24"
                      role="img"
                      aria-label="Mastercard"
                    >
                      <circle cx="13" cy="12" r="10" fill="#eb001b" />
                      <circle
                        cx="23"
                        cy="12"
                        r="10"
                        fill="#f79e1b"
                        fillOpacity=".85"
                      />
                    </svg>
                  </span>
                )}
              </label>
            ))}
            {options.some(([method]) => method === "card") && (
              <p className="text-sm muted">
                Card details are entered on Easypaisa&apos;s secure page.
              </p>
            )}
            {result.quote && !options.length && (
              <p role="alert">
                No payment method is available for this order. Please contact
                the shop.
              </p>
            )}
          </fieldset>
        </div>
        <div className="order-summary">
          <p className="lv-eyebrow">YOUR SELECTION</p>
          <h2 className="text-2xl mb-5">Order summary</h2>
          {result.loading && <p role="status">Checking current prices…</p>}
          {result.error && <p role="alert">{result.error}</p>}
          {result.quote?.lines.map((line) => (
            <p key={line.variant_id} className="border-b py-3">
              <strong className="lv-checkout-item-title">
                {line.description}
              </strong>
              <span className="lv-checkout-item-meta">
                {[line.size, line.color].filter(Boolean).join(" · ")} · Qty{" "}
                {line.quantity}
              </span>
              <span className="lv-checkout-item-amount">
                {formatPrice(line.total)}
              </span>
            </p>
          ))}
          {Object.values(result.unavailable).map((message, i) => (
            <p role="alert" key={i}>
              {message}
            </p>
          ))}
          {result.quote && <QuoteTotals quote={result.quote} />}
          <Link className="underline block my-4" href="/cart">
            Edit bag
          </Link>
          {error && (
            <p role="alert" className="my-4 text-red-800">
              {error}
            </p>
          )}
          <Button
            className=" w-full"
            disabled={
              busy ||
              (!attempt &&
                (result.loading ||
                  !result.quote ||
                  !selectedMethod ||
                  !!Object.keys(result.unavailable).length))
            }
          >
            {busy
              ? "Creating your order…"
              : attempt
                ? "Retry saved checkout"
                : selectedMethod === "cod"
                  ? "Place order"
                  : "Place order and pay securely"}
          </Button>
        </div>
      </form>
    </section>
  );
}
