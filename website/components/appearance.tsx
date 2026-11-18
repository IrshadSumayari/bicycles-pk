"use client";
import { useEffect, useSyncExternalStore } from "react";
import { Sun, Moon, Monitor } from "lucide-react";
import { appearanceMode, darkAppearance } from "@/lib/appearance";

const KEY = "storefront-appearance",
  EVENT = "storefront-appearance-change";
let memory: string | null = null;
function snapshot() {
  try {
    return appearanceMode(localStorage.getItem(KEY));
  } catch {
    return appearanceMode(memory);
  }
}
const serverSnapshot = () => "system" as const;
function subscribe(listener: () => void) {
  window.addEventListener("storage", listener);
  window.addEventListener(EVENT, listener);
  return () => {
    window.removeEventListener("storage", listener);
    window.removeEventListener(EVENT, listener);
  };
}
export function Appearance() {
  const mode = useSyncExternalStore(subscribe, snapshot, serverSnapshot);
  useEffect(() => {
    const media = window.matchMedia("(prefers-color-scheme: dark)");
    const apply = () => {
      document.documentElement.classList.toggle(
        "dark",
        darkAppearance(mode, media.matches),
      );
      document.documentElement.style.colorScheme =
        mode === "system" ? (media.matches ? "dark" : "light") : mode;
    };
    apply();
    media.addEventListener("change", apply);
    return () => media.removeEventListener("change", apply);
  }, [mode]);
  const Icon = mode === "light" ? Sun : mode === "dark" ? Moon : Monitor;
  return (
    <label className="appearance-control">
      <Icon size={18} aria-hidden="true" />
      <span className="sr-only">Appearance</span>
      <select
        aria-label="Appearance"
        value={mode}
        onChange={(e) => {
          const value = appearanceMode(e.target.value);
          memory = value;
          try {
            localStorage.setItem(KEY, value);
          } catch {
            /* In-memory appearance still works. */
          }
          window.dispatchEvent(new Event(EVENT));
        }}
      >
        <option value="system">System</option>
        <option value="light">Light</option>
        <option value="dark">Dark</option>
      </select>
    </label>
  );
}
