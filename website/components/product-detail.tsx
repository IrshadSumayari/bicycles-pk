"use client";
import {
  categoryHref,
  colourSwatch,
  groupedSpecs,
  sectionOfCategory,
  specSubtitle,
} from "../../shared/bicycles";
import { SizeFinder } from "./size-finder";
import { PurchaseReassurance } from "./purchase-reassurance";
import { brand } from "@/lib/brand";
import Image from "next/image";
import Link from "next/link";
import { useRouter } from "next/navigation";
import {
  Bike,
  ChevronLeft,
  ChevronRight,
  Maximize2,
  Minus,
  Plus,
  Ruler,
  Share2,
  Store,
  Truck,
  X,
} from "lucide-react";
import { Button } from "./ui/button";
import { Input } from "./ui/input";
import { useEffect, useRef, useState } from "react";
import {
  combinations,
  formatPrice,
  imageUrl,
  stockText,
  variantOptions,
  whatsappLink,
} from "@/lib/helpers";
import { fetchLiveProduct, onlyInStockVariant } from "@/lib/live-product";
import type { CatalogRow, Product, Related, Variant } from "@/lib/types";
import { useStore } from "./store-provider";
function firstChoice(variants: Variant[]) {
  return variants.find((v) => v.stock_level !== "out_of_stock") ?? variants[0];
}
type Dimension = "size" | "color" | "fit";
const optionLabel = (dimension: Dimension) =>
  ({ color: "Colour", fit: "Model", size: "Size" })[dimension];
// Product page in the style of the detail reference: gallery on the left, a
// sticky purchase panel on the right, add-ons, then overview and specs.
export function ProductDetail({
  initial,
  pageUrl,
  models = [],
  addOns = [],
}: {
  initial: Product;
  pageUrl: string;
  models?: Related[];
  addOns?: CatalogRow[];
}) {
  const bag = useStore();
  const [product, setProduct] = useState<Product | null>(initial);
  const [selectedId, setSelectedId] = useState(
    firstChoice(initial.variants)?.variant_id ?? "",
  );
  const [refreshing, setRefreshing] = useState(true);
  const [error, setError] = useState("");
  const [imageIndex, setImageIndex] = useState(0);
  const [quantity, setQuantity] = useState("1");
  const [refreshKey, setRefreshKey] = useState(0);
  const [shared, setShared] = useState("");
  const zoom = useRef<HTMLDialogElement>(null);
  const finder = useRef<HTMLDialogElement>(null);
  const specGroups = groupedSpecs(initial.specs);
  const subtitle = specSubtitle(initial.specs, initial.category ?? undefined);
  const section = sectionOfCategory(initial.category ?? undefined);
  useEffect(() => {
    let controller: AbortController | undefined;
    let stopped = false;
    let request = 0;
    async function refresh() {
      const current = ++request;
      controller?.abort();
      const check = new AbortController();
      controller = check;
      const timeout = setTimeout(() => check.abort(), 5000);
      try {
        const latest = await fetchLiveProduct(initial.slug, check.signal);
        if (current === request && !stopped) {
          setProduct(latest);
          setError("");
        }
      } catch {
        if (current === request && !stopped)
          setError(
            "Could not refresh availability. Please try again before ordering.",
          );
      } finally {
        clearTimeout(timeout);
        if (current === request && !stopped) setRefreshing(false);
      }
    }
    void refresh();
    const focus = () => {
      if (document.visibilityState === "visible") {
        setRefreshing(true);
        void refresh();
      }
    };
    window.addEventListener("focus", focus);
    document.addEventListener("visibilitychange", focus);
    return () => {
      stopped = true;
      ++request;
      controller?.abort();
      window.removeEventListener("focus", focus);
      document.removeEventListener("visibilitychange", focus);
    };
  }, [initial.slug, refreshKey]);
  const variants = (product ?? initial).variants;
  const selected =
    product?.variants.find((v) => v.variant_id === selectedId) ??
    firstChoice(product?.variants ?? []);
  const selection = {
    size: selected?.size ?? "",
    color: selected?.color ?? "",
    fit: selected?.fit ?? "",
  };
  function choose(dimension: Dimension, value: string) {
    if (!product) return;
    const desired = { ...selection, [dimension]: value };
    const candidates = combinations(product.variants, desired);
    const matchingColor = combinations(
      product.variants,
      dimension === "color"
        ? { color: value }
        : { color: desired.color, [dimension]: value },
    );
    const next =
      firstChoice(candidates.filter((v) => v.stock_level !== "out_of_stock")) ??
      firstChoice(
        matchingColor.filter((v) => v.stock_level !== "out_of_stock"),
      );
    if (next) {
      setSelectedId(next.variant_id);
      // Show the chosen colour's first photo when there is one.
      const colour = next.color?.trim().toLowerCase();
      setImageIndex(
        Math.max(
          0,
          product.images.findIndex(
            (i) => !!colour && i.variant_color?.trim().toLowerCase() === colour,
          ),
        ),
      );
    }
  }
  const options = (dimension: Dimension) =>
    variants.some((v) => v[dimension] !== null)
      ? variantOptions(
          variants,
          dimension,
          dimension === "color"
            ? {}
            : dimension === "size"
              ? { color: selection.color }
              : { color: selection.color, size: selection.size },
        )
      : [];
  const images = (product ?? initial).images;
  const image = images[imageIndex] ?? images[0];
  const url = imageUrl(image?.storage_path);
  const orderLink = selected
    ? whatsappLink(
        brand.whatsapp ?? "",
        initial.title,
        selected.size ?? "",
        selected.color ?? "",
        pageUrl,
        selected.fit ?? "",
      )
    : null;
  const canOrder =
    !!product &&
    !!selected &&
    selected.stock_level !== "out_of_stock" &&
    !refreshing &&
    !error;
  const quantityValid =
    Number.isInteger(Number(quantity)) &&
    Number(quantity) >= 1 &&
    Number(quantity) <= 10;
  const addToBag = () => {
    if (!canOrder || !selected || !quantityValid) return;
    bag.dispatch({
      type: "add",
      variant_id: selected.variant_id,
      quantity: Number(quantity),
    });
    bag.open();
  };
  const share = async () => {
    try {
      if (navigator.share) {
        await navigator.share({ title: initial.title, url: pageUrl });
        return;
      }
      await navigator.clipboard.writeText(pageUrl);
      setShared("Link copied");
    } catch {
      setShared("");
    }
  };
  const step = (by: number) =>
    setImageIndex((imageIndex + by + images.length) % images.length);
  const price = selected?.price ?? initial.min_price;
  const compare =
    selected?.compare_at_price && selected.compare_at_price > price
      ? selected.compare_at_price
      : null;
  const colours = options("color");
  const sizes = options("size");
  const fits = options("fit");
  return (
    <div className="lv-pdp">
      <section className="lv-pdp-top">
        <div className="lv-pdp-gallery">
          <div className="lv-pdp-stage">
            {url ? (
              <Image
                src={url}
                alt={image.alt || initial.title}
                fill
                sizes="(max-width:900px) 100vw, 62vw"
                loading="eager"
                fetchPriority="high"
                preload
              />
            ) : (
              <span className="lv-pdp-fallback" aria-hidden="true">
                <Bike size={120} strokeWidth={0.75} />
              </span>
            )}
            {url && (
              <button
                type="button"
                className="lv-pdp-zoom"
                aria-label="Zoom image"
                onClick={() => zoom.current?.showModal()}
              >
                <Maximize2 size={18} />
              </button>
            )}
            {images.length > 1 && (
              <div className="lv-pdp-arrows" aria-label="Product image navigation">
                <button
                  type="button"
                  aria-label="Previous product image"
                  onClick={() => step(-1)}
                >
                  <ChevronLeft size={20} />
                </button>
                <span aria-live="polite">
                  {imageIndex + 1} / {images.length}
                </span>
                <button
                  type="button"
                  aria-label="Next product image"
                  onClick={() => step(1)}
                >
                  <ChevronRight size={20} />
                </button>
              </div>
            )}
          </div>
          {images.length > 1 && (
            <div className="lv-pdp-thumbs">
              {images.map((item, i) => {
                const src = imageUrl(item.storage_path);
                return (
                  src && (
                    <button
                      type="button"
                      key={item.storage_path}
                      className={imageIndex === i ? "active" : ""}
                      aria-pressed={imageIndex === i}
                      aria-label={"View product image " + (i + 1)}
                      onClick={() => setImageIndex(i)}
                    >
                      <Image src={src} alt="" width={120} height={90} />
                    </button>
                  )
                );
              })}
            </div>
          )}
        </div>
        <aside className="lv-pdp-panel">
          <nav className="lv-pdp-crumbs" aria-label="Breadcrumb">
            <Link href="/">Home</Link>
            {section && (
              <>
                <span aria-hidden="true">/</span>
                <Link href={section.href}>{section.label}</Link>
              </>
            )}
            {initial.category && (
              <>
                <span aria-hidden="true">/</span>
                <Link href={categoryHref(initial.category)}>
                  {initial.category}
                </Link>
              </>
            )}
          </nav>
          <h1>{initial.title}</h1>
          {subtitle && <p className="lv-pdp-subtitle">{subtitle}</p>}
          {models.length > 0 && (
            <div className="lv-pdp-models">
              <p className="lv-pdp-label">Models</p>
              <div>
                <span className="lv-pdp-model" aria-current="page">
                  <ModelPhoto path={images[0]?.storage_path ?? null} />
                  <strong>{initial.title}</strong>
                  <span>{formatPrice(initial.min_price)}</span>
                </span>
                {models.map((m) => (
                  <Link
                    key={m.style_id}
                    className="lv-pdp-model"
                    href={`/products/${m.slug}`}
                  >
                    <ModelPhoto path={m.image_path} />
                    <strong>{m.title}</strong>
                    <span>{formatPrice(m.min_price)}</span>
                  </Link>
                ))}
              </div>
            </div>
          )}
          <div className="lv-pdp-price">
            {formatPrice(price)}
            {compare ? <del>{formatPrice(compare)}</del> : null}
          </div>
          <div aria-live="polite" className="lv-pdp-stock">
            <p className={canOrder ? "stock-indicator" : "muted"}>
              {!product
                ? "This item is no longer available."
                : stockText(selected?.stock_level ?? "out_of_stock")}
            </p>
            {refreshing && <p className="muted">Checking availability…</p>}
            {error && (
              <p role="alert" className="form-error">
                {error}
              </p>
            )}
          </div>
          {colours.length > 0 && (
            <fieldset
              className="lv-pdp-option"
              disabled={!product || refreshing}
            >
              <legend>
                Colour: <strong>{selection.color}</strong>
              </legend>
              <div className="lv-pdp-swatches">
                {colours.map((option) => (
                  <button
                    type="button"
                    key={option.value}
                    className={
                      selection.color === option.value ? "selected" : ""
                    }
                    style={{ background: colourSwatch(option.value) }}
                    disabled={!option.available}
                    aria-pressed={selection.color === option.value}
                    aria-label={
                      "Colour: " +
                      (option.value || "One colour") +
                      (!option.available ? ", out of stock" : "")
                    }
                    title={option.value}
                    onClick={() => {
                      choose("color", option.value);
                      setQuantity("1");
                    }}
                  />
                ))}
              </div>
            </fieldset>
          )}
          {([
            ["size", sizes],
            ["fit", fits],
          ] as const).map(
            ([dimension, list]) =>
              list.length > 0 && (
                <fieldset
                  key={dimension}
                  className="lv-pdp-option"
                  disabled={!product || refreshing}
                >
                  <legend>
                    {optionLabel(dimension)}:{" "}
                    <strong>{selection[dimension]}</strong>
                  </legend>
                  <div className="lv-pdp-sizes">
                    {list.map((option) => (
                      <button
                        type="button"
                        key={option.value}
                        className={
                          selection[dimension] === option.value
                            ? "selected"
                            : ""
                        }
                        disabled={!option.available}
                        aria-pressed={selection[dimension] === option.value}
                        aria-label={
                          optionLabel(dimension) +
                          ": " +
                          (option.value || "One option") +
                          (!option.available ? ", out of stock" : "")
                        }
                        onClick={() => {
                          choose(dimension, option.value);
                          setQuantity("1");
                        }}
                      >
                        {option.value || "One option"}
                      </button>
                    ))}
                  </div>
                  {dimension === "size" && (
                    <div className="lv-pdp-size-links">
                      <button
                        type="button"
                        onClick={() => finder.current?.showModal()}
                      >
                        <Ruler size={16} /> What&apos;s my size?
                      </button>
                      <Link href="/fit-guide">Size guide</Link>
                    </div>
                  )}
                </fieldset>
              ),
          )}
          <div className="lv-pdp-delivery">
            <p className="lv-pdp-label">Delivery</p>
            <div>
              <Truck size={20} aria-hidden="true" />
              <p>
                <strong>Ship to home</strong>
                <span>
                  {initial.bulky
                    ? "Delivery across Pakistan. Bikes include a bulky item charge; add assembly at checkout to get it ready to ride. "
                    : "Delivery across Pakistan. "}
                  See the{" "}
                  <Link href="/policies/shipping-policy">shipping policy</Link>.
                </span>
              </p>
            </div>
            <div>
              <Store size={20} aria-hidden="true" />
              <p>
                <strong>Store pickup</strong>
                <span>
                  {initial.bulky
                    ? "Free. Collect it assembled and checked; choose pickup at checkout."
                    : "Free. Choose pickup at checkout."}
                </span>
              </p>
            </div>
          </div>
          <div className="lv-pdp-buy">
            <div className="quantity">
              <Button
                variant="ghost"
                size="icon"
                aria-label="Decrease quantity"
                onClick={() =>
                  setQuantity(String(Math.max(1, (Number(quantity) || 1) - 1)))
                }
              >
                <Minus size={16} />
              </Button>
              <Input
                aria-label="Quantity"
                type="number"
                min={1}
                max={10}
                step={1}
                value={quantity}
                onChange={(e) => setQuantity(e.target.value)}
              />
              <Button
                variant="ghost"
                size="icon"
                aria-label="Increase quantity"
                onClick={() =>
                  setQuantity(String(Math.min(10, (Number(quantity) || 1) + 1)))
                }
              >
                <Plus size={16} />
              </Button>
            </div>
            <button
              type="button"
              className="lv-pdp-add"
              disabled={!canOrder || !quantityValid}
              onClick={addToBag}
            >
              Add to bag
            </button>
          </div>
          {!quantityValid && (
            <p role="alert" className="form-error">
              Choose 1 to 10 pieces.
            </p>
          )}
          <div className="lv-pdp-secondary">
            {orderLink && canOrder && (
              <a href={orderLink} target="_blank" rel="noopener noreferrer">
                Order on WhatsApp
              </a>
            )}
            <button type="button" onClick={share}>
              <Share2 size={16} /> Share
            </button>
            <button
              type="button"
              disabled={refreshing}
              onClick={() => {
                setRefreshing(true);
                setRefreshKey((k) => k + 1);
              }}
            >
              Refresh availability
            </button>
            <span aria-live="polite">{shared}</span>
          </div>
          <PurchaseReassurance policy={initial.purchase_policy} />
        </aside>
      </section>
      {addOns.length > 0 && (
        <section className="lv-pdp-addons" aria-labelledby="addons-title">
          <h2 id="addons-title">Complete your ride</h2>
          <div>
            {addOns.map((p) => (
              <AddOn key={p.style_id} product={p} />
            ))}
          </div>
        </section>
      )}
      <section className="lv-pdp-overview" aria-labelledby="overview-title">
        <div className="lv-pdp-overview-copy">
          <p className="lv-eyebrow">
            {(section?.label ?? "Bicycles.pk").toUpperCase()}
          </p>
          <h2 id="overview-title">{initial.title}</h2>
          {subtitle && <p className="lv-pdp-tagline">{subtitle}</p>}
          {initial.description && (
            <div className="rich-content whitespace-pre-line">
              {initial.description}
            </div>
          )}
        </div>
        <div className="lv-pdp-specs">
          <h2>Specifications</h2>
          {specGroups.length === 0 && (
            <p className="muted">
              Specifications for this product are on their way.{" "}
              <Link href="/pages/contact">Ask us</Link> if you need a detail now.
            </p>
          )}
          {specGroups.map((group, i) => (
            <details key={group.title} open={i === 0}>
              <summary>{group.title}</summary>
              <dl>
                {group.rows.map((row) => (
                  <div key={row.key}>
                    <dt>{row.label}</dt>
                    <dd>{row.value}</dd>
                  </div>
                ))}
              </dl>
            </details>
          ))}
          <details>
            <summary>Delivery and returns</summary>
            <p>
              Review our{" "}
              <Link href="/policies/shipping-policy">shipping policy</Link> and{" "}
              <Link href="/policies/refund-policy">
                exchange and return policy
              </Link>{" "}
              before placing your order.
            </p>
          </details>
        </div>
      </section>
      <div className="lv-mobile-buybar" aria-label="Quick purchase">
        <div>
          <strong>{formatPrice(price)}</strong>
          <span>
            {[selection.size, selection.color].filter(Boolean).join(" · ") ||
              "Your selection"}
            {Number(quantity) > 1 ? " · Qty " + quantity : ""}
          </span>
        </div>
        <Button disabled={!canOrder || !quantityValid} onClick={addToBag}>
          Add to bag
        </Button>
      </div>
      {url && (
        <dialog ref={zoom} className="lv-zoom-dialog" aria-label="Zoomed image">
          <form method="dialog">
            <button aria-label="Close zoom">
              <X size={20} />
            </button>
          </form>
          <div className="lv-zoom-stage">
            <Image
              src={url}
              alt={image.alt || initial.title}
              fill
              sizes="100vw"
            />
          </div>
        </dialog>
      )}
      <dialog
        ref={finder}
        aria-labelledby="size-finder-title"
        className="lv-size-dialog"
      >
        <div className="flex justify-between gap-8 mb-5">
          <h2 id="size-finder-title">What&apos;s my size?</h2>
          <form method="dialog">
            <Button variant="outline">Close</Button>
          </form>
        </div>
        <SizeFinder
          initialMode={section?.id === "kids" ? "kids" : "adult"}
          productSizes={sizes.map((o) => o.value)}
          onPick={(size) => {
            choose("size", size);
            setQuantity("1");
            finder.current?.close();
          }}
        />
        <Link href="/fit-guide">Full size guide</Link>
      </dialog>
    </div>
  );
}
function ModelPhoto({ path }: { path: string | null }) {
  const src = imageUrl(path);
  return (
    <span className="lv-pdp-model-photo">
      {src ? (
        <Image src={src} alt="" width={120} height={90} />
      ) : (
        <Bike size={28} strokeWidth={1} aria-hidden="true" />
      )}
    </span>
  );
}
// Add-on card with a quick add: adds straight to the bag when there's only
// one in-stock option, otherwise opens the product to choose.
function AddOn({ product }: { product: CatalogRow }) {
  const bag = useStore();
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const src = imageUrl(product.image_path);
  const href = `/products/${product.slug}`;
  const soldOut = product.stock_level === "out_of_stock";
  const quickAdd = async () => {
    setBusy(true);
    try {
      const variant = onlyInStockVariant(await fetchLiveProduct(product.slug));
      if (variant) {
        bag.dispatch({ type: "add", variant_id: variant.variant_id, quantity: 1 });
        bag.open();
        return;
      }
    } catch {}
    finally {
      setBusy(false);
    }
    router.push(href);
  };
  return (
    <article className="lv-pdp-addon">
      <Link href={href} className="lv-pdp-addon-photo" aria-label={product.title}>
        {src ? (
          <Image src={src} alt="" fill sizes="160px" />
        ) : (
          <Bike size={36} strokeWidth={1} aria-hidden="true" />
        )}
      </Link>
      <div>
        <h3>
          <Link href={href}>{product.title}</Link>
        </h3>
        {(product.colors ?? []).filter(Boolean).length > 1 && (
          <span className="lv-pdp-addon-swatches" aria-label="Colours">
            {(product.colors ?? [])
              .filter(Boolean)
              .slice(0, 5)
              .map((c) => (
                <span
                  key={c}
                  title={c}
                  style={{ background: colourSwatch(c) }}
                />
              ))}
          </span>
        )}
        <p>{formatPrice(product.min_price)}</p>
      </div>
      <button
        type="button"
        className="lv-pdp-addon-add"
        disabled={busy || soldOut}
        aria-label={(soldOut ? "Sold out: " : "Add ") + product.title}
        onClick={quickAdd}
      >
        {soldOut ? "Sold out" : <Plus size={18} />}
      </button>
    </article>
  );
}
