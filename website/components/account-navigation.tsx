"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";
export function AccountNavigation() {
  const path = usePathname();
  if (path === "/account/sign-in") return null;
  return (
    <nav className="lv-account-nav" aria-label="Account navigation">
      {[
        { href: "/account", label: "My profile" },
        { href: "/account/orders", label: "My orders" },
        { href: "/account/track", label: "Track order" },
        { href: "/fit-guide", label: "Size guide" },
      ].map((l) => (
        <Link
          key={l.href}
          href={l.href}
          aria-current={
            path === l.href ||
            (l.href !== "/account" && path.startsWith(l.href + "/"))
              ? "page"
              : undefined
          }
        >
          {l.label}
        </Link>
      ))}
    </nav>
  );
}
