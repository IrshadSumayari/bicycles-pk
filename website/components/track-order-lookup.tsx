"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { normalizedOrderNumber } from "../../shared/orderTracking";
import { ordersService } from "@/lib/orders";
import { Button } from "./ui/button";
export function TrackOrderLookup() {
  const router = useRouter();
  const [number, setNumber] = useState(""),
    [busy, setBusy] = useState(false),
    [error, setError] = useState("");
  async function submit() {
    if (busy) return;
    setError("");
    const orderNo = normalizedOrderNumber(number);
    if (!orderNo) {
      setError("Enter your order number, for example WEB-000123.");
      return;
    }
    setBusy(true);
    try {
      await ordersService.detail(orderNo);
      router.push("/account/orders/" + encodeURIComponent(orderNo));
    } catch {
      setError(
        "We could not load this order. Check the number, make sure you are signed in with the email used for the order, and try again.",
      );
      setBusy(false);
    }
  }
  return (
    <section className="lv-track-lookup">
      <p className="lv-eyebrow">FOLLOW YOUR LADYVOGUE ORDER</p>
      <h1>Track my order</h1>
      <p>
        Enter the order number from your confirmation. You can track orders
        placed with this signed-in account.
      </p>
      <form
        className="space-y-4"
        onSubmit={(e) => {
          e.preventDefault();
          void submit();
        }}
      >
        <label>
          Order number
          <input
            className="field"
            placeholder="WEB-000123"
            autoComplete="off"
            autoCapitalize="characters"
            maxLength={24}
            value={number}
            disabled={busy}
            onChange={(e) => setNumber(e.target.value)}
          />
        </label>
        {error && <p role="alert">{error}</p>}
        <Button disabled={busy}>
          {busy ? "Finding your order…" : "Track order"}
        </Button>
      </form>
      <Link className="underline" href="/account/orders">
        See all my orders
      </Link>
    </section>
  );
}
