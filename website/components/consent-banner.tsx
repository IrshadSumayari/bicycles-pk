"use client";
import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { Button } from "./ui/button";
import { readConsent, analyticsId, type Consent } from "@/lib/consent";
export function ConsentBanner({ nonce }: { nonce: string }) {
  const [choice, setChoice] = useState<Consent>(null),
    [ready, setReady] = useState(false),
    [open, setOpen] = useState(false);
  const started = useRef(false),
    id = analyticsId(process.env.NEXT_PUBLIC_ANALYTICS_ID);
  useEffect(() => {
    const timer = setTimeout(() => {
      setChoice(readConsent(document.cookie));
      setReady(true);
    }, 0);
    return () => clearTimeout(timer);
  }, []);
  useEffect(() => {
    if (!id || !ready) return;
    const target = window as Window & {
      dataLayer?: unknown[];
      gtag?: (...args: unknown[]) => void;
    };
    Object.assign(window, { ["ga-disable-" + id]: choice !== "accepted" });
    if (choice === "accepted" && !started.current) {
      started.current = true;
      target.dataLayer ??= [];
      target.gtag = function (...args: unknown[]) {
        target.dataLayer!.push(args);
      };
      target.gtag("js", new Date());
      target.gtag("consent", "default", {
        analytics_storage: "granted",
        ad_storage: "denied",
        ad_user_data: "denied",
        ad_personalization: "denied",
      });
      target.gtag("config", id, {
        allow_google_signals: false,
        allow_ad_personalization_signals: false,
      });
      const script = document.createElement("script");
      script.id = "consented-analytics";
      script.async = true;
      script.nonce = nonce;
      script.src =
        "https://www.googletagmanager.com/gtag/js?id=" + encodeURIComponent(id);
      document.head.appendChild(script);
    }
    if (choice === "rejected") {
      target.gtag?.("consent", "update", {
        analytics_storage: "denied",
        ad_storage: "denied",
      });
      document.getElementById("consented-analytics")?.remove();
      started.current = false;
      for (const part of document.cookie.split(";")) {
        const name = part.split("=")[0].trim();
        if (!/^(_ga|_gid)(_|$)/.test(name)) continue;
        document.cookie = name + "=; Max-Age=0; Path=/";
        const labels = location.hostname.split(".");
        for (let i = 0; i < labels.length - 1; i++)
          document.cookie =
            name + "=; Max-Age=0; Path=/; Domain=." + labels.slice(i).join(".");
      }
    }
  }, [choice, ready, id, nonce]);
  function choose(value: Exclude<Consent, null>) {
    document.cookie =
      "storefront-analytics=" +
      value +
      "; Max-Age=15552000; Path=/; SameSite=Lax" +
      (location.protocol === "https:" ? "; Secure" : "");
    setChoice(value);
    setOpen(false);
  }
  return (
    <>
      <div className="center py-4">
        <Button variant="link" onClick={() => setOpen(true)}>
          Privacy choices
        </Button>
      </div>
      {ready && (choice === null || open) && (
        <section className="consent-banner" aria-label="Analytics preferences">
          <h2>Privacy choices</h2>
          <p>
            Essential storage keeps your sign-in and shopping bag working.
            Optional analytics{" "}
            {id
              ? "help us understand visits and load only if you accept."
              : "are not configured on this website."}{" "}
            <Link className="underline" href="/policies/privacy-policy">
              Privacy policy
            </Link>
          </p>
          <div className="flex flex-wrap gap-3">
            <Button variant="outline" onClick={() => choose("rejected")}>
              Reject analytics
            </Button>
            <Button variant="outline" onClick={() => choose("accepted")}>
              Accept analytics
            </Button>
          </div>
        </section>
      )}
    </>
  );
}
