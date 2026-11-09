"use client";
import Link from "next/link";
import { X } from "lucide-react";
import { useEffect, useState } from "react";
import home from "@/content/home.json";
const KEY = "bicycles-announcement-dismissed";
// Thin bar above the header. Dismissal is remembered per announcement text
// in this browser only; it shows again when the text changes.
export function AnnouncementBar() {
  const { text, link } = home.announcement;
  const [hidden, setHidden] = useState(false);
  useEffect(() => {
    try {
      if (localStorage.getItem(KEY) === text) setHidden(true);
    } catch {}
  }, [text]);
  if (!text || hidden) return null;
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
          setHidden(true);
          try {
            localStorage.setItem(KEY, text);
          } catch {}
        }}
      >
        <X size={16} />
      </button>
    </div>
  );
}
