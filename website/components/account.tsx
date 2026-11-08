"use client";
import { Button } from "./ui/button";
import { Input } from "./ui/input";
import { getErrorMessage } from "@/lib/errors";
import Image from "next/image";
import Link from "next/link";
import { useState } from "react";

import { browserClient } from "@/lib/supabase-browser";
export function Account({ next }: { next: string }) {
  const configured =
    !!process.env.NEXT_PUBLIC_SUPABASE_URL &&
    !!process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  const [email, setEmail] = useState(""),
    [code, setCode] = useState(""),
    [sent, setSent] = useState(false),
    [busy, setBusy] = useState(false),
    [error, setError] = useState("");

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError("");
    try {
      const client = browserClient();
      if (sent) {
        if (!/^\d{6}$/.test(code))
          throw new Error("Enter the six-digit code from your email");
        const { error } = await client.auth.verifyOtp({
          email: email.trim(),
          token: code,
          type: "email",
        });
        if (error) throw error;
        window.location.assign(next);
      } else {
        const { error } = await client.auth.signInWithOtp({
          email: email.trim(),
        });
        if (error) throw error;
        setSent(true);
      }
    } catch (e) {
      setError(getErrorMessage(e));
    } finally {
      setBusy(false);
    }
  }
  return (
    <div className="lv-signin">
      <div className="lv-signin-editorial">
        <Image
          src="/ladyvogue/nightwear.webp"
          alt="Ivory satin nightwear in soft light"
          fill
          sizes="(max-width:760px) 100vw,45vw"
        />
        <div>
          <p className="lv-eyebrow">YOUR LITTLE CORNER OF LADYVOGUE</p>
          <h2>
            Welcome to <br />
            <em>your everyday.</em>
          </h2>
        </div>
      </div>
      <form
        onSubmit={submit}
        className="account-panel space-y-5"
        aria-busy={busy}
      >
        <p className="lv-eyebrow">GOOD TO SEE YOU</p>
        <h1 className="text-3xl">Make yourself at home.</h1>
        <p>
          Sign in to manage your details and follow your orders. We’ll email you
          a six-digit code—no password needed.
        </p>
        {!configured && (
          <p role="status" className="lv-form-notice">
            Sign-in is not available yet. Please check back soon.
          </p>
        )}
        <label className="block">
          Email
          <Input
            className="field"
            type="email"
            required
            autoComplete="email"
            autoCapitalize="none"
            spellCheck={false}
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            disabled={sent || busy}
          />
        </label>
        {sent && (
          <>
            <p id="verification-hint" role="status">
              Check your email for the six-digit code.
            </p>
            <label className="block">
              Six-digit code
              <Input
                className="field lv-verification-code"
                autoFocus
                aria-describedby="verification-hint"
                inputMode="numeric"
                autoComplete="one-time-code"
                pattern="[0-9]{6}"
                maxLength={6}
                required
                value={code}
                onChange={(e) => setCode(e.target.value.replace(/\D/g, ""))}
              />
            </label>
          </>
        )}
        {error && <p role="alert">{error}</p>}
        <Button className="w-full" disabled={busy || !configured}>
          {busy ? "Please wait…" : sent ? "Verify code" : "Send code"}
        </Button>
        {sent && (
          <Button
            variant="outline"
            className="lv-change-email"
            type="button"
            disabled={busy}
            onClick={() => {
              setSent(false);
              setCode("");
            }}
          >
            Change email / send again
          </Button>
        )}
        <Link className="lv-link" href="/collections">
          Back to the collection
        </Link>
      </form>
    </div>
  );
}
