"use client";
import { Button } from "./ui/button";
import { Input } from "./ui/input";
import { getErrorMessage } from "@/lib/errors";
import { useState } from "react";

import { browserClient } from "@/lib/supabase-browser";
import { normalizePhone } from "@/lib/account";
export function Profile({
  id,
  initial,
}: {
  id: string;
  initial: {
    full_name: string | null;
    phone: string | null;
    marketing_consent: boolean;
    email_marketing_consent: boolean | null;
    sms_marketing_consent: boolean | null;
  };
}) {
  const [name, setName] = useState(initial.full_name ?? ""),
    [phone, setPhone] = useState(normalizePhone(initial.phone ?? "")),
    [emailConsent, setEmailConsent] = useState(initial.email_marketing_consent),
    [smsConsent, setSmsConsent] = useState(initial.sms_marketing_consent),
    [message, setMessage] = useState(""),
    [busy, setBusy] = useState(false);

  async function act(kind: "save" | "link" | "out") {
    setBusy(true);
    setMessage("");
    try {
      const c = browserClient();
      if (kind === "out") {
        const { error } = await c.auth.signOut();
        if (error) throw error;
        window.location.replace("/account/sign-in");
        return;
      }
      if (kind === "save") {
        if (!name.trim() || name.length > 200 || phone.length > 50)
          throw new Error(
            "Enter your name (up to 200 characters) and a valid phone number",
          );
        const { data: saved, error } = await c
          .from("customer_accounts")
          .update({
            full_name: name.trim(),
            phone: normalizePhone(phone) || null,
            email_marketing_consent: emailConsent,
            sms_marketing_consent: smsConsent,
          })
          .eq("id", id)
          .select("email_marketing_consent,sms_marketing_consent")
          .single();
        if (error) throw error;
        setEmailConsent(saved.email_marketing_consent);
        setSmsConsent(saved.sms_marketing_consent);
        setPhone(normalizePhone(phone));
        setMessage("Your profile has been saved.");
      } else {
        const { data, error } = await c.rpc("link_customer_account");
        if (error) throw error;
        setMessage(
          (data as { status?: string })?.status === "linked"
            ? "Your shop account is linked."
            : "Your phone has not been verified for this link. Please visit the shop with your account email and phone so our staff can link it after checking your identity.",
        );
      }
    } catch (e) {
      setMessage(getErrorMessage(e));
    } finally {
      setBusy(false);
    }
  }
  return (
    <div className="lv-profile max-w-lg space-y-5">
      <p className="lv-eyebrow">YOUR LITTLE CORNER</p>
      <h1 className="text-3xl">My profile</h1>
      <p className="lv-account-intro">
        Keep your details and preferences up to date.
      </p>
      <form
        className="space-y-5"
        onSubmit={(e) => {
          e.preventDefault();
          void act("save");
        }}
      >
        <label className="block">
          Name
          <Input
            className="field"
            required
            autoComplete="name"
            maxLength={200}
            value={name}
            onChange={(e) => setName(e.target.value)}
          />
        </label>
        <label className="block">
          Phone
          <Input
            className="field"
            type="tel"
            autoComplete="tel"
            maxLength={50}
            value={phone}
            onChange={(e) => {
              setPhone(e.target.value);
              setSmsConsent(null);
            }}
          />
        </label>
        <fieldset className="space-y-3">
          <legend>News and offers (optional)</legend>
          <label className="flex gap-3">
            <input
              type="checkbox"
              checked={emailConsent === true}
              onChange={(e) => setEmailConsent(e.target.checked)}
            />
            Email me promotions
          </label>
          <label className="flex gap-3">
            <input
              type="checkbox"
              checked={smsConsent === true}
              onChange={(e) => setSmsConsent(e.target.checked)}
            />
            Send me promotional SMS
          </label>
          <p className="muted">
            You can withdraw either permission here. Saving a new phone clears
            its old permission; save the new number first, then choose SMS
            offers if you want them.
          </p>
        </fieldset>
        <Button className="" disabled={busy}>
          Save profile
        </Button>
      </form>
      <Button
        variant="outline"
        className=""
        disabled={busy}
        onClick={() => void act("link")}
      >
        Link my shop account
      </Button>
      <p className="muted">
        If your phone is not verified, the shop can check your identity and link
        your account in person.
      </p>
      <p role="status">{message}</p>
      <Button
        className="underline"
        disabled={busy}
        onClick={() => void act("out")}
      >
        Sign out
      </Button>
    </div>
  );
}
