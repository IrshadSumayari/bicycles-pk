"use client";
import Link from "next/link";
import { X } from "lucide-react";
import { useSyncExternalStore } from "react";
import home from "@/content/home.json";
const KEY = "bicycles-announcement-dismissed";
const listeners = new Set<() => void>();
function subscribe(listener: () => void) {
  listeners.add(listener);
  window.addEventListener("storage", listener);
  return () => {
    listeners.delete(listener);
    window.removeEventListener("storage", listener);
  };
}
function dismissedText(): string | null {
  try {
    return localStorage.getItem(KEY);
  } catch {
    return null;
  }
}
// Thin bar above the header. Dismissal is remembered per announcement text
// in this browser only; it shows again when the text changes.
export function AnnouncementBar() {
  const { text, link } = home.announcement;
  const dismissed = useSyncExternalStore(subscribe, dismissedText, () => null);
  if (!text || dismissed === text) return null;
  return (
    <div className="lv-announcement" role="region" aria-label="Announcement">
      <span className="lv-announcement-dot" aria-hidden="true" />
      {text}{" "}
      {link?.href && <Link href={link.href}>{link.label}</Link>}
      <button
        type="button"
        className="lv-announcement-close"
        aria-label="Dismiss announcement"
        onClick={() => {
          try {
            localStorage.setItem(KEY, text);
          } catch {}
          listeners.forEach((l) => l());
        }}
      >
        <X size={16} />
      </button>
    </div>
  );
}
