import React, { useEffect, useState } from "react";
import { ShieldCheck } from "lucide-react";
import { Input } from "@/components/ui/input";
import { supabase } from "../../lib/supabase";
import { useAuth } from "../../context/AuthContext";
import { getErrorMessage } from "../../lib/errors";

// Administrators and managers must confirm each sign-in with an authenticator
// app (Google Authenticator, Microsoft Authenticator, 1Password and similar).
// The database ignores their role until this step is done, so this screen is
// a guide, not the protection itself.
type Enrollment = { factorId: string; qr: string; secret: string };

export function MfaGate() {
  const { profile, mfaStep, refreshMfa, signOut } = useAuth();
  const [enrollment, setEnrollment] = useState<Enrollment | null>(null);
  const [factorId, setFactorId] = useState<string | null>(null);
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    async function prepare() {
      setError(null);
      try {
        const { data, error } = await supabase.auth.mfa.listFactors();
        if (error) throw error;
        if (mfaStep === "verify") {
          const verified = data.totp.find((f) => f.status === "verified");
          if (!cancelled) setFactorId(verified?.id ?? null);
          return;
        }
        // A setup that was started and never finished blocks a new one.
        for (const factor of data.all) {
          if (factor.factor_type === "totp" && factor.status === "unverified") {
            await supabase.auth.mfa.unenroll({ factorId: factor.id });
          }
        }
        const enrolled = await supabase.auth.mfa.enroll({
          factorType: "totp",
          friendlyName: "Bicycles POS",
        });
        if (enrolled.error) throw enrolled.error;
        if (!cancelled) {
          setEnrollment({
            factorId: enrolled.data.id,
            qr: enrolled.data.totp.qr_code,
            secret: enrolled.data.totp.secret,
          });
          setFactorId(enrolled.data.id);
        }
      } catch (e) {
        if (!cancelled) setError(getErrorMessage(e));
      }
    }
    void prepare();
    return () => {
      cancelled = true;
    };
  }, [mfaStep]);

  const handleVerify = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!factorId) return;
    setBusy(true);
    setError(null);
    try {
      const { error } = await supabase.auth.mfa.challengeAndVerify({
        factorId,
        code: code.trim(),
      });
      if (error) throw error;
      setCode("");
      await refreshMfa();
    } catch (e) {
      const message = getErrorMessage(e);
      setError(
        /invalid|expired/i.test(message)
          ? "That code is wrong or has expired. Enter the current code from the app."
          : message,
      );
    } finally {
      setBusy(false);
    }
  };

  const enrolling = mfaStep === "enroll";

  return (
    <div className="min-h-screen bg-lightgray flex items-center justify-center p-4">
      <div className="bg-card rounded-2xl shadow-xs border border-border p-8 max-w-md w-full space-y-5">
        <div className="text-center space-y-2">
          <ShieldCheck className="mx-auto h-10 w-10 text-primary" aria-hidden="true" />
          <h1 className="text-xl font-bold text-link">
            {enrolling ? "Set up your authenticator app" : "Enter your authenticator code"}
          </h1>
          <p className="text-sm text-bodytext">
            {enrolling
              ? `${profile?.role === "admin" ? "Administrator" : "Manager"} accounts need a code from an authenticator app at every sign-in. Scan this code with the app, then enter the 6-digit code it shows.`
              : "Open your authenticator app and enter the 6-digit code for Bicycles POS."}
          </p>
        </div>

        {enrolling && enrollment && (
          <div className="space-y-3 text-center">
            <img
              src={enrollment.qr}
              alt="QR code for your authenticator app"
              className="mx-auto h-48 w-48 rounded-lg bg-white p-2"
            />
            <p className="text-xs text-bodytext">
              Can't scan it? Enter this key in the app:
              <br />
              <code className="text-link break-all select-all">{enrollment.secret}</code>
            </p>
          </div>
        )}

        {error && (
          <p className="text-sm text-error text-center" role="alert">
            {error}
          </p>
        )}

        {mfaStep === "verify" && !factorId && !error ? null : (
          <form onSubmit={handleVerify} className="space-y-4">
            <label htmlFor="mfa-code" className="block text-sm font-semibold text-link">
              6-digit code
            </label>
            <Input
              id="mfa-code"
              value={code}
              onChange={(e) => setCode(e.target.value.replace(/\D/g, "").slice(0, 6))}
              className="input h-11 text-center tracking-[0.5em] text-lg"
              inputMode="numeric"
              autoComplete="one-time-code"
              placeholder="000000"
              required
              minLength={6}
              maxLength={6}
              autoFocus
            />
            <button
              type="submit"
              disabled={busy || code.length !== 6 || !factorId}
              className="btn btn-primary w-full h-11 font-semibold disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {busy ? "Checking..." : enrolling ? "Turn on and continue" : "Continue"}
            </button>
          </form>
        )}

        <p className="text-xs text-bodytext text-center">
          Lost your phone? Ask the project owner to reset your authenticator in
          Supabase, then set it up again here.
        </p>
        <div className="text-center">
          <button onClick={() => signOut()} className="btn btn-secondary btn-md">
            Sign out
          </button>
        </div>
      </div>
    </div>
  );
}
