"use client";
import { readProductGuide } from "../../shared/productGuide";
import { SupplierSizeChart } from "./size-chart";
import {
  lingerieFilterLabels,
  lingerieValueLabel,
} from "../../shared/lingerie";
import { isJewelleryCategory } from "../../shared/jewellery";
import {
  bagDimensions,
  isBagCategory,
  parseBagDetails,
} from "../../shared/bags";
import { hasModelPhotos, readTryOn } from "../../shared/tryOn";
import { TryOnViewer } from "./try-on-viewer";
import { PurchaseReassurance } from "./purchase-reassurance";
import { brand } from "@/lib/brand";
import Image from "next/image";
import Link from "next/link";
import { Minus, Plus, Ruler, ChevronLeft, ChevronRight } from "lucide-react";
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
import type { Product, Variant } from "@/lib/types";
import { useStore } from "./store-provider";
function firstChoice(variants: Variant[]) {
  return variants.find((v) => v.stock_level !== "out_of_stock") ?? variants[0];
}
export function ProductDetail({
  initial,
  pageUrl,
}: {
  initial: Product;
  pageUrl: string;
}) {
  const bag = useStore();
  const jewellery = isJewelleryCategory(initial.category ?? undefined);
  const [product, setProduct] = useState<Product | null>(initial);
  const [selectedId, setSelectedId] = useState(
    firstChoice(initial.variants)?.variant_id ?? "",
  );
  const [refreshing, setRefreshing] = useState(true);
  const [error, setError] = useState("");
  const [imageIndex, setImageIndex] = useState(0);
  const [view, setView] = useState<"photos" | "model">("photos");
  const [quantity, setQuantity] = useState("1");
  const [refreshKey, setRefreshKey] = useState(0);
  const guide = readProductGuide(initial.product_guide ?? {});
  const bagItem = !jewellery && isBagCategory(initial.category);
  const bagInfo = bagItem ? parseBagDetails(guide.fit) : null;
  const bagRows: [string, string][] = bagInfo
    ? (
        [
          ["Dimensions", bagDimensions(bagInfo.details)],
          ["Strap drop", bagInfo.details.strap_drop],
          ["Closure", bagInfo.details.closure],
          ["Compartments", bagInfo.details.compartments],
          ["What fits", bagInfo.details.fits],
        ] as [string, string | null | undefined][]
      ).filter((row): row is [string, string] => !!row[1])
    : [];
  const optionLabel = (dimension: "size" | "color" | "fit") =>
    jewellery
      ? { color: "Finish", fit: "Design", size: "Size / length" }[dimension]
      : bagItem
        ? { color: "Colour", fit: "Style", size: "Size" }[dimension]
        : dimension;
  const hasChart =
    !!guide.size_chart ||
    (initial.size_chart != null &&
      JSON.stringify(initial.size_chart) !== "{}" &&
      JSON.stringify(initial.size_chart) !== "[]");
  const chart = useRef<HTMLDialogElement>(null);
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
        const base = process.env.NEXT_PUBLIC_SUPABASE_URL;
        const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
        if (!base || !key) throw new Error("Unavailable");
        const response = await fetch(
          `${base.replace(/\/$/, "")}/rest/v1/rpc/catalog_product`,
          {
            method: "POST",
            headers: { apikey: key, "Content-Type": "application/json" },
            body: JSON.stringify({ p_slug: initial.slug }),
            cache: "no-store",
            signal: check.signal,
          },
        );
        if (!response.ok) throw new Error("Unavailable");
        const latest: Product | null = await response.json();
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
  const selected =
    product?.variants.find((v) => v.variant_id === selectedId) ??
    firstChoice(product?.variants ?? []);
  const selection = {
    size: selected?.size ?? "",
    color: selected?.color ?? "",
    fit: selected?.fit ?? "",
  };
  function choose(dimension: "size" | "color" | "fit", value: string) {
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
  const images = (product ?? initial).images;
  const tryOn = readTryOn((product ?? initial).try_on, initial.style_id);
  // 360° appears only with real angle photos or a 3D model for this style.
  const hasTryOn = !!tryOn.model_path || hasModelPhotos(tryOn);
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
  return (
    <div className="lv-product-page">
      <div className="breadcrumb">
        <Link href="/">Home</Link> / <Link href="/collections">Products</Link> /{" "}
        {initial.title}
      </div>
      <section className="product-detail">
        <div className="product-gallery">
          {hasTryOn && (
            <div
              className="lv-gallery-views"
              role="group"
              aria-label="Product view"
            >
              {(["photos", "model"] as const).map((v) => (
                <Button
                  key={v}
                  variant="outline"
                  className={view === v ? "selected" : ""}
                  aria-pressed={view === v}
                  onClick={() => setView(v)}
                >
                  {v === "photos" ? "Photos" : "360° model"}
                </Button>
              ))}
            </div>
          )}
          {view === "model" && hasTryOn ? (
            <TryOnViewer
              title={initial.title}
              tryOn={tryOn}
              swatches={variantOptions(
                (product ?? initial).variants,
                "color",
                {},
              )}
              color={selection.color}
              disabled={!product || refreshing}
              onColor={(value) => {
                choose("color", value);
                setQuantity("1");
              }}
            />
          ) : (
            <>
              {images.length > 1 && (
                <div className="gallery-thumbnails">
                  {images.map((item, i) => {
                    const src = imageUrl(item.storage_path);
                    return (
                      src && (
                        <button
                          key={item.storage_path}
                          className={imageIndex === i ? "active" : ""}
                          aria-pressed={imageIndex === i}
                          aria-label={"View product image " + (i + 1)}
                          onClick={() => setImageIndex(i)}
                        >
                          <Image src={src} alt="" width={70} height={100} />
                        </button>
                      )
                    );
                  })}
                </div>
              )}
              <div className="gallery-main relative aspect-[2/3]">
                {url ? (
                  <Image
                    src={url}
                    alt={image.alt || initial.title}
                    fill
                    sizes="(max-width:760px) 100vw,560px"
                    loading="eager"
                    fetchPriority="high"
                    preload
                  />
                ) : (
                  <span className="photo-fallback" aria-hidden="true">
                    LV
                  </span>
                )}
                {images.length > 1 && (
                  <div
                    className="lv-gallery-controls"
                    aria-label="Product image navigation"
                  >
                    <Button
                      variant="ghost"
                      size="icon"
                      aria-label="Previous product image"
                      onClick={() =>
                        setImageIndex(
                          (imageIndex - 1 + images.length) % images.length,
                        )
                      }
                    >
                      <ChevronLeft size={20} />
                    </Button>
                    <span aria-live="polite">
                      {imageIndex + 1} / {images.length}
                    </span>
                    <Button
                      variant="ghost"
                      size="icon"
                      aria-label="Next product image"
                      onClick={() =>
                        setImageIndex((imageIndex + 1) % images.length)
                      }
                    >
                      <ChevronRight size={20} />
                    </Button>
                  </div>
                )}
              </div>
            </>
          )}
        </div>
        <div className="product-information">
          <p className="lv-eyebrow">LADYVOGUE · EVERYDAY, BEAUTIFULLY.</p>
          <h1>{initial.title}</h1>
          <div className="detail-price">
            {formatPrice(selected?.price ?? initial.min_price)}
            {selected?.compare_at_price &&
            selected.compare_at_price > selected.price ? (
              <del>{formatPrice(selected.compare_at_price)}</del>
            ) : null}
          </div>
          <div aria-live="polite">
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
          {(["color", "size", "fit"] as const).map((dimension) => {
            if (
              !(product ?? initial).variants.some((v) => v[dimension] !== null)
            )
              return null;
            const options = variantOptions(
              (product ?? initial).variants,
              dimension,
              dimension === "color"
                ? {}
                : dimension === "size"
                  ? { color: selection.color }
                  : { color: selection.color, size: selection.size },
            );
            return (
              <fieldset
                key={dimension}
                className="variant-options"
                disabled={!product || refreshing}
              >
                <legend className="capitalize">
                  {optionLabel(dimension)}
                  : <strong>{selection[dimension]}</strong>
                </legend>
                <div>
                  {options.map((option) => (
                    <Button
                      variant="outline"
                      key={option.value}
                      className={
                        selection[dimension] === option.value ? "selected" : ""
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
                    </Button>
                  ))}
                </div>
              </fieldset>
            );
          })}
          {hasChart && (
            <Button variant="link" onClick={() => chart.current?.showModal()}>
              <Ruler size={16} />
              Size chart
            </Button>
          )}
          <Link
            className="lv-product-fit-link"
            href={
              jewellery
                ? "/jewellery#choosing"
                : bagItem
                  ? "/bags#size-guide"
                  : "/fit-guide"
            }
          >
            <Ruler size={16} />{" "}
            {jewellery
              ? "Size and material guidance"
              : bagItem
                ? "What fits? See the bag size guide"
              : "Need a little help with sizing?"}
          </Link>
          <div className="purchase-row">
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
            <Button disabled={!canOrder || !quantityValid} onClick={addToBag}>
              Add to bag
            </Button>
          </div>
          {!quantityValid && (
            <p role="alert" className="form-error">
              Choose 1 to 10 pieces.
            </p>
          )}
          {orderLink && canOrder && (
            <Button asChild variant="outline" className="w-full">
              <a href={orderLink} target="_blank" rel="noopener noreferrer">
                Order on WhatsApp
              </a>
            </Button>
          )}
          <Button
            variant="link"
            disabled={refreshing}
            onClick={() => {
              setRefreshing(true);
              setRefreshKey((key) => key + 1);
            }}
          >
            Refresh availability
          </Button>
          <PurchaseReassurance policy={initial.purchase_policy} />
          <Link
            href={bagItem ? "/bags#size-guide" : "/fit-guide"}
            className="flex gap-2 items-center underline"
          >
            <Ruler size={18} />
            {bagItem ? "Bag size guide" : "Find your fit"}
          </Link>
          <dl className="product-meta">
            <div>
              <dt>Category:</dt>
              <dd>{initial.category}</dd>
            </div>
            {Object.entries(initial.lingerie ?? {})
              .filter(([, value]) => value)
              .map(([key, value]) => (
                <div key={key}>
                  <dt>
                    {key === "composition"
                      ? "Material composition"
                      : (lingerieFilterLabels[
                          key as keyof typeof lingerieFilterLabels
                        ] ?? key)}
                    :
                  </dt>
                  <dd>{lingerieValueLabel(key, value!)}</dd>
                </div>
              ))}
            {initial.material && (
              <div>
                <dt>Material:</dt>
                <dd>{initial.material}</dd>
              </div>
            )}
            {bagRows.map(([label, value]) => (
              <div key={label}>
                <dt>{label}:</dt>
                <dd>{value}</dd>
              </div>
            ))}
          </dl>
          {!hasChart && !bagItem && (
            <p className="lv-chart-missing">
              A size chart has not been supplied for this product.{" "}
              <Link href="/pages/contact">Ask us about sizing</Link> before
              ordering.
            </p>
          )}
          {(["included", "fit", "care"] as const)
            .map((k) => [k, k === "fit" && bagInfo ? bagInfo.notes : guide[k]] as const)
            .filter(([, text]) => text?.trim())
            .map(([k, text]) => (
              <details className="product-description" key={k}>
                <summary>
                  {
                    {
                      included: bagItem ? "What’s included" : "Included pieces",
                      fit: bagItem ? "Notes" : "Fit notes",
                      care: "Care instructions",
                    }[k]
                  }
                </summary>
                <p className="whitespace-pre-line">{text}</p>
              </details>
            ))}
          <details open className="product-description">
            <summary>Description</summary>
            <div className="rich-content whitespace-pre-line">
              {initial.description}
            </div>
          </details>
          <details className="product-description">
            <summary>Delivery & returns</summary>
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
          <strong>{formatPrice(selected?.price ?? initial.min_price)}</strong>
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
      {hasChart && (
        <dialog
          ref={chart}
          aria-labelledby="size-chart-title"
          className="lv-size-dialog"
        >
          <div className="flex justify-between gap-8 mb-5">
            <h2 id="size-chart-title">Size chart</h2>
            <form method="dialog">
              <Button variant="outline">Close</Button>
            </form>
          </div>
          <p className="muted">For {initial.title}</p>
          {guide.size_chart ? (
            <SupplierSizeChart chart={guide.size_chart} />
          ) : (
            <>
              <p>
                This is the existing size-scheme chart. Use only units and
                measurement labels explicitly stated below; missing units are
                not assumed. Confirm with us if unclear.
              </p>
              <Chart value={initial.size_chart} />
            </>
          )}
          <Link href="/fit-guide">How to measure</Link>
        </dialog>
      )}
    </div>
  );
}
function Chart({ value }: { value: Product["size_chart"] }) {
  if (Array.isArray(value)) {
    const rows = value.filter(
      (
        row,
      ): row is {
        [key: string]: Exclude<Product["size_chart"], undefined> | undefined;
      } => !!row && typeof row === "object" && !Array.isArray(row),
    );
    if (rows.length === value.length && rows.length) {
      const keys = [...new Set(rows.flatMap((row) => Object.keys(row)))];
      return (
        <div className="overflow-x-auto">
          <table>
            <caption className="sr-only">Measurements by size</caption>
            <thead>
              <tr>
                {keys.map((key) => (
                  <th key={key} scope="col">
                    {key.replaceAll("_", " ")}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {rows.map((row, index) => (
                <tr key={index}>
                  {keys.map((key) => (
                    <td key={key}>{String(row[key] ?? "—")}</td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      );
    }
    return (
      <ul>
        {value.map((item, index) => (
          <li key={index}>
            <Chart value={item} />
          </li>
        ))}
      </ul>
    );
  }
  if (value && typeof value === "object")
    return (
      <dl className="space-y-3">
        {Object.entries(value).map(([key, item]) => (
          <div key={key}>
            <dt className="font-semibold capitalize">
              {key.replaceAll("_", " ")}
            </dt>
            <dd>{item !== undefined && <Chart value={item} />}</dd>
          </div>
        ))}
      </dl>
    );
  return <span>{String(value ?? "—")}</span>;
}
