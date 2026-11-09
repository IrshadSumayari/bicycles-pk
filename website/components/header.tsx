"use client";
import { BrandLogo } from "./brand-logo";
import { buildShopMenus } from "@/lib/shop-navigation";
import { brand } from "@/lib/brand";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import {
  Search,
  UserRound,
  ShoppingBag,
  Menu,
  X,
  ChevronDown,
} from "lucide-react";
import { useStore } from "./store-provider";
import { Button } from "./ui/button";
import { Input } from "./ui/input";
import { Sheet, SheetContent, SheetTitle, SheetDescription } from "./ui/sheet";
import { Appearance } from "./appearance";
import { AnnouncementBar } from "./announcement-bar";
import home from "@/content/home.json";
type NavItem = {
  label: string;
  href: string;
  children: { label: string; href: string }[];
};
export function Header({ nav }: { nav: NavItem[] }) {
  const [menu, setMenu] = useState(false),
    [search, setSearch] = useState(false);
  const pathname = usePathname();
  const desktopNav = useRef<HTMLElement>(null);
  useEffect(() => {
    const closeOutside = (event: PointerEvent) => {
      if (
        event.target instanceof Node &&
        !desktopNav.current?.contains(event.target)
      ) {
        desktopNav.current
          ?.querySelectorAll<HTMLDetailsElement>("details[open]")
          .forEach((item) => {
            item.open = false;
          });
      }
    };
    document.addEventListener("pointerdown", closeOutside);
    return () => document.removeEventListener("pointerdown", closeOutside);
  }, []);
  const menuButton = useRef<HTMLButtonElement>(null);
  const searchButton = useRef<HTMLButtonElement>(null);
  const { lines, open } = useStore();
  const count = lines.length;
  const collections = nav.map((item) => ({
    slug: item.href.split("/").pop() || "",
  }));
  const navigation = buildShopMenus(collections);
  const links = navigation.map((item) =>
    item.children.length ? (
      <details
        className="nav-item lv-shop-menu"
        key={item.label}
        onToggle={(event) => {
          const current = event.currentTarget;
          if (current.open)
            current
              .closest("nav")
              ?.querySelectorAll<HTMLDetailsElement>("details[open]")
              .forEach((other) => {
                if (other !== current) other.open = false;
              });
        }}
      >
        <summary>
          {item.label}
          <ChevronDown size={13} aria-hidden="true" />
        </summary>
        <div className="lv-menu-panel">
          <Link
            className="lv-menu-all"
            href={item.href}
            onClick={(event) => {
              setMenu(false);
              event.currentTarget.closest("details")?.removeAttribute("open");
            }}
          >
            {item.label === "Help"
              ? "Contact Bicycles.pk"
              : "Shop all " + item.label.toLowerCase()}
          </Link>
          {item.children
            .filter((child) => child.href !== item.href)
            .map((child) => (
              <Link
                key={child.href}
                href={child.href}
                onClick={(event) => {
                  setMenu(false);
                  event.currentTarget
                    .closest("details")
                    ?.removeAttribute("open");
                }}
              >
                {child.label}
              </Link>
            ))}
        </div>
      </details>
    ) : (
      <div className="nav-item" key={item.label}>
        <Link href={item.href} onClick={() => setMenu(false)}>
          {item.label}
        </Link>
      </div>
    ),
  );
  return (
    <>
      <a className="skip-link" href="#MainContent">
        Skip to content
      </a>
      <div className={pathname === "/" ? "lv-header-shell lv-overlay" : "lv-header-shell"}>
      <AnnouncementBar />
      <header className="site-header">
        <Button
          variant="ghost"
          size="icon"
          ref={menuButton}
          className="mobile-menu icon-button"
          aria-label="Open navigation"
          aria-expanded={menu}
          onClick={() => setMenu(true)}
        >
          <Menu />
        </Button>
        <Link className="brand" href="/" aria-label={`${brand.name} home`}>
          <BrandLogo />
        </Link>
        <nav
          ref={desktopNav}
          className="main-nav"
          aria-label="Main navigation"
          onKeyDown={(event) => {
            if (event.key === "Escape") {
              const details =
                event.currentTarget.querySelector<HTMLDetailsElement>(
                  "details[open]",
                );
              if (details) {
                details.open = false;
                details.querySelector("summary")?.focus();
              }
            }
          }}
        >
          {links}
        </nav>
        <div className="header-actions">
          <Button
            ref={searchButton}
            variant="ghost"
            size="icon"
            className="icon-button"
            aria-label="Search products"
            aria-expanded={search}
            onClick={() => setSearch(!search)}
          >
            <Search size={23} strokeWidth={1.5} />
          </Button>
          <Link className="icon-button" href="/account" aria-label="My account">
            <UserRound size={21} strokeWidth={1.5} />
          </Link>
          <Button
            variant="ghost"
            size="icon"
            className="icon-button bag-button"
            aria-label={`Shopping bag, ${count} lines`}
            onClick={open}
          >
            <ShoppingBag size={23} strokeWidth={1.5} />
            {count > 0 && <span>{count}</span>}
          </Button>
          <Link className="lv-header-cta" href={home.headerCta.href}>
            {home.headerCta.label}
          </Link>
        </div>
      </header>
      <nav className="lv-mobile-categories" aria-label="Shop categories">
        <Link
          href="/collections"
          aria-current={pathname === "/collections" ? "page" : undefined}
        >
          Shop all
        </Link>
        {navigation
          .filter((item) => item.label !== "Help")
          .map((item) => (
          <Link key={item.href} href={item.href}>
            {item.label}
          </Link>
        ))}
      </nav>
      </div>
      <Sheet open={menu} onOpenChange={setMenu}>
        <SheetContent
          side="left"
          className="mobile-navigation p-6 overflow-y-auto"
          onCloseAutoFocus={(event) => {
            event.preventDefault();
            menuButton.current?.focus();
          }}
        >
          <SheetTitle>{brand.name}</SheetTitle>
          <SheetDescription>Explore our collections</SheetDescription>
          <nav aria-label="Mobile navigation">
            {links}
            <div className="nav-item">
              <Link href="/account" onClick={() => setMenu(false)}>
                My account
              </Link>
            </div>
          </nav>
          <Appearance />
        </SheetContent>
      </Sheet>
      {search && (
        <form
          className="header-search"
          action="/search"
          role="search"
          onKeyDown={(event) => {
            if (event.key === "Escape") {
              setSearch(false);
              searchButton.current?.focus();
            }
          }}
        >
          <Input
            autoFocus
            name="q"
            placeholder="Search bikes, helmets, tyres…"
            aria-label="Search products"
          />
          <Button type="submit">Search</Button>
          <Button
            type="button"
            variant="ghost"
            size="icon"
            aria-label="Close search"
            onClick={() => {
              setSearch(false);
              searchButton.current?.focus();
            }}
          >
            <X />
          </Button>
        </form>
      )}
    </>
  );
}
