"use client";
import { useRef, useState, useSyncExternalStore } from "react";
import { SlidersHorizontal, X } from "lucide-react";
import { Card } from "./ui/card";
import { Button } from "./ui/button";
import { Sheet, SheetContent, SheetTitle, SheetDescription } from "./ui/sheet";
const subscribeToMobile = (onChange: () => void) => {
  const media = window.matchMedia("(max-width: 760px)");
  media.addEventListener("change", onChange);
  return () => media.removeEventListener("change", onChange);
};
const mobileSnapshot = () => window.matchMedia("(max-width: 760px)").matches;
const serverSnapshot = () => false;
export function FilterPanel({
  children,
  filters,
  count,
  page,
  sort,
  path,
  query,
}: {
  children: React.ReactNode;
  filters: React.ReactNode;
  count: number;
  page: number;
  sort: string;
  path: string;
  query: string;
}) {
  const [open, setOpen] = useState(false);
  const trigger = useRef<HTMLButtonElement>(null);
  const heading = useRef<HTMLHeadingElement>(null);
  const mobile = useSyncExternalStore(
    subscribeToMobile,
    mobileSnapshot,
    serverSnapshot,
  );
  return (
    <section className="catalog-shell">
      <div className="catalog-toolbar">
        <Button
          ref={trigger}
          variant="ghost"
          aria-haspopup={mobile ? "dialog" : undefined}
          aria-expanded={open}
          aria-controls={open ? "catalog-filter-panel" : undefined}
          onClick={() => setOpen(!open)}
        >
          <SlidersHorizontal size={17} /> Filter
        </Button>
        <span className="muted">
          {count} {count === 1 ? "product" : "products"}
        </span>
        <label className="ml-auto">
          Sort by{" "}
          <select
            aria-label="Sort by"
            name="sort"
            value={sort}
            onChange={(event) => {
              const params = new URLSearchParams(query);
              params.set("sort", event.target.value);
              window.location.assign(path + "?" + params.toString());
            }}
          >
            <option value="new">Newest</option>
            <option value="price_asc">Price, low to high</option>
            <option value="price_desc">Price, high to low</option>
          </select>
        </label>
      </div>
      <div
        className={
          open && !mobile ? "catalog-layout with-filters" : "catalog-layout"
        }
      >
        {open && !mobile && (
          <Card id="catalog-filter-panel" className="filter-panel filters-open">
            <div className="flex justify-between items-center mb-5">
              <h2 className="text-lg">Filter products</h2>
              <Button
                variant="ghost"
                size="icon"
                aria-label="Close filters"
                onClick={() => setOpen(false)}
              >
                <X size={16} />
              </Button>
            </div>
            {filters}
          </Card>
        )}
        <div data-page={page}>{children}</div>
      </div>
      {mobile && (
        <Sheet open={open} onOpenChange={setOpen}>
          <SheetContent
            side="bottom"
            id="catalog-filter-panel"
            className="lv-mobile-filter-sheet"
            onOpenAutoFocus={(event) => {
              event.preventDefault();
              heading.current?.focus();
            }}
            onCloseAutoFocus={(event) => {
              event.preventDefault();
              trigger.current?.focus();
            }}
          >
            <SheetTitle ref={heading} tabIndex={-1}>
              Find your perfect match
            </SheetTitle>
            <SheetDescription>
              Refine by size, colour, product details and price.
            </SheetDescription>
            {filters}
          </SheetContent>
        </Sheet>
      )}
    </section>
  );
}
