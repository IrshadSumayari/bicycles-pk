"use client";
import { lineKey } from "@/lib/cart";
import Link from "next/link";
import { Minus, Plus, Trash2, ShoppingBag } from "lucide-react";
import { useStore } from "./store-provider";
import { useBagQuote, QuoteTotals } from "./cart-quote";
import { formatPrice } from "@/lib/helpers";
import { Button } from "./ui/button";
import { Input } from "./ui/input";
import { Card } from "./ui/card";
import { Sheet, SheetContent, SheetTitle, SheetDescription } from "./ui/sheet";
export function CartContents({ drawer = false }: { drawer?: boolean }) {
  const { lines, ready, dispatch, setCartOpen } = useStore();
  const result = useBagQuote(lines, "pickup");
  if (!ready) return <p role="status">Loading your shopping bag…</p>;
  if (!lines.length)
    return (
      <div className="empty-state">
        <ShoppingBag size={42} strokeWidth={1} />
        <p className="lv-eyebrow">ROOM FOR SOMETHING LOVELY</p>
        <h2>Your bag is waiting for you.</h2>
        <p>Explore bicycles, accessories and parts.</p>
        <Button asChild>
          <Link href="/collections" onClick={() => setCartOpen(false)}>
            Continue shopping
          </Link>
        </Button>
      </div>
    );
  return (
    <div className={drawer ? "" : "cart-layout"} aria-busy={result.loading}>
      <div className="cart-lines">
        {lines.map((line) => {
          const quoted = result.quotedLines?.[lineKey(line)],
            unavailable = result.unavailable[lineKey(line)];
          const title = quoted?.description ?? unavailable ?? "Checking item…";
          return (
            <article
              className={`cart-line ${unavailable ? "unavailable" : ""}`}
              key={lineKey(line)}
            >
              <div className="lv-bag-item-content">
                <strong>{title}</strong>
                {quoted && (
                  <>
                    <p className="muted">
                      {[quoted.size, quoted.color, quoted.sku]
                        .filter(Boolean)
                        .join(" · ")}
                    </p>
                    <p>{formatPrice(quoted.unit_price)} each</p>
                  </>
                )}
                <div className="quantity">
                  <Button
                    variant="ghost"
                    size="icon"
                    aria-label={`Decrease ${title}`}
                    disabled={!quoted || result.loading || line.quantity <= 1}
                    onClick={() =>
                      dispatch({
                        type: "set",
                        variant_id: line.variant_id,
                        quantity: line.quantity - 1,
                      })
                    }
                  >
                    <Minus size={14} />
                  </Button>
                  <Input
                    aria-label={`Quantity for ${quoted?.description ?? "unavailable item"}`}
                    disabled={!quoted || result.loading}
                    type="number"
                    min={1}
                    max={10}
                    step={1}
                    value={line.quantity}
                    onChange={(e) =>
                      dispatch({
                        type: "set",
                        variant_id: line.variant_id,
                        quantity: Number(e.target.value),
                      })
                    }
                  />
                  <Button
                    variant="ghost"
                    size="icon"
                    aria-label={`Increase ${title}`}
                    disabled={!quoted || result.loading || line.quantity >= 10}
                    onClick={() =>
                      dispatch({
                        type: "set",
                        variant_id: line.variant_id,
                        quantity: line.quantity + 1,
                      })
                    }
                  >
                    <Plus size={14} />
                  </Button>
                </div>
              </div>
              <div className="lv-bag-item-actions">
                {quoted && (
                  <p className="lv-bag-line-total">
                    <span>Item total</span>
                    <strong>{formatPrice(quoted.total)}</strong>
                  </p>
                )}
                <Button
                  variant="ghost"
                  className="remove"
                  aria-label={`Remove ${title}`}
                  onClick={() =>
                    dispatch({
                      type: "remove",
                      variant_id: line.variant_id,
                    })
                  }
                >
                  <Trash2 size={16} />
                  <span>Remove</span>
                </Button>
              </div>
            </article>
          );
        })}
      </div>
      <Card className="cart-summary">
        <p className="lv-eyebrow">THE LITTLE DETAILS</p>
        <h2>Your order</h2>
        {result.loading && (
          <p role="status">Updating prices and availability…</p>
        )}
        {result.error && <p role="alert">{result.error}</p>}
        {result.quote && <QuoteTotals quote={result.quote} />}
        <p className="muted">
          Shipping and any applicable charges are confirmed at checkout.
        </p>
        {Object.keys(result.unavailable).length > 0 ? (
          <p role="alert">
            Remove unavailable items before checkout. Totals include available
            items only.
          </p>
        ) : result.quote && !result.loading && !result.error ? (
          <Button asChild className="w-full">
            <Link href="/checkout" onClick={() => setCartOpen(false)}>
              Proceed to checkout
            </Link>
          </Button>
        ) : null}
        {drawer && (
          <Link
            className="text-link"
            href="/cart"
            onClick={() => setCartOpen(false)}
          >
            View shopping bag
          </Link>
        )}
      </Card>
    </div>
  );
}
export function CartDrawer() {
  const { cartOpen, setCartOpen } = useStore();
  return (
    <Sheet open={cartOpen} onOpenChange={setCartOpen}>
      <SheetContent className="cart-drawer overflow-y-auto p-6 w-full sm:max-w-md">
        <SheetTitle>Shopping bag</SheetTitle>
        <SheetDescription>
          Current prices are verified with the shop.
        </SheetDescription>
        <CartContents drawer />
      </SheetContent>
    </Sheet>
  );
}
