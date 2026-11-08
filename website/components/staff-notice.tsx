"use client";
import { useState } from "react";
import { Button } from "./ui/button";
import { browserClient } from "@/lib/supabase-browser";
import { getErrorMessage } from "@/lib/errors";

// Staff and customers share one sign-in, but staff accounts have no customer
// profile, orders or requests. Explain that and offer a way out.
export function StaffNotice({ className = "" }: { className?: string }) {
  const [busy, setBusy] = useState(false),
    [message, setMessage] = useState("");

  async function signOut() {
    setBusy(true);
    setMessage("");
    try {
      const { error } = await browserClient().auth.signOut();
      if (error) throw error;
      window.location.replace("/account/sign-in");
    } catch (e) {
      setMessage(getErrorMessage(e));
      setBusy(false);
    }
  }

  return (
    <div className={`max-w-xl space-y-4 ${className}`}>
      <h1>This is a staff account</h1>
      <p className="muted">
        You are signed in with a staff email. Staff accounts are used in the
        LadyVogue POS, not for shopping. To place orders, sign out and sign in with your customer email.
      </p>
      <Button disabled={busy} onClick={() => void signOut()}>
        {busy ? "Signing out…" : "Sign out"}
      </Button>
      <p role="status">{message}</p>
    </div>
  );
}
