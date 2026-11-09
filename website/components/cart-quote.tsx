"use client";
import { useEffect, useState } from "react";
import { lineKey, type CartLine } from "@/lib/cart";
import { ordersService, type OrderQuote, type QuoteLine } from "@/lib/orders";
import { formatPrice } from "@/lib/helpers";
import { getErrorMessage } from "@/lib/errors";
export function useBagQuote(
  lines: CartLine[],
  fulfilment: string,
  assembly = false,
) {
  const fingerprint = JSON.stringify([lines, fulfilment, assembly]);
  const [result, setResult] = useState<{
    fingerprint: string;
    quote: OrderQuote | null;
    quotedLines?: Record<string, QuoteLine>;
    unavailable: Record<string, string>;
    loading: boolean;
    error: string;
  }>({
    fingerprint: "",
    quote: null,
    unavailable: {},
    loading: true,
    error: "",
  });
  useEffect(() => {
    let live = true;
    const timer = setTimeout(async () => {
      if (!lines.length) {
        if (live)
          setResult({
            fingerprint,
            quote: null,
            unavailable: {},
            loading: false,
            error: "",
          });
        return;
      }
      if (live) setResult((r) => ({ ...r, loading: true, error: "" }));
      try {
        const checks = await Promise.all(
          lines.map(async (line) => {
            try {
              const q = await ordersService.quote([line], fulfilment);
              return { line, quoted: q.lines[0] };
            } catch (error) {
              if (!(
                error &&
                typeof error === "object" &&
                "code" in error &&
                error.code === "P0001"
              ))
                throw error;
              return { line, error: getErrorMessage(error) };
            }
          }),
        );
        const unavailable: Record<string, string> = {};
        for (const check of checks)
          if (check.error || check.quoted?.availability === "out_of_stock")
            unavailable[lineKey(check.line)] =
              check.error ||
              `${check.quoted?.description} is unavailable in this quantity`;
        const valid = lines.filter((l) => !unavailable[lineKey(l)]);
        const plain = valid.length
          ? await ordersService.quote(valid, fulfilment)
          : null;
        const quote =
          plain && assembly && plain.assembly_available
            ? await ordersService.quote(valid, fulfilment, true)
            : plain;
        if (live)
          setResult({
            fingerprint,
            quote,
            quotedLines: Object.fromEntries(
              checks.flatMap((c) =>
                c.quoted ? [[lineKey(c.line), c.quoted]] : [],
              ),
            ),
            unavailable,
            loading: false,
            error: "",
          });
      } catch (error) {
        if (live)
          setResult({
            fingerprint,
            quote: null,
            unavailable: {},
            loading: false,
            error: getErrorMessage(error),
          });
      }
    }, 200);
    return () => {
      live = false;
      clearTimeout(timer);
    };
  }, [lines, fulfilment, assembly, fingerprint]);
  return result.fingerprint === fingerprint
    ? result
    : { ...result, quote: null, loading: true };
}
export function QuoteTotals({
  quote,
}: {
  quote: Pick<OrderQuote, "subtotal" | "tax" | "delivery_fee" | "total"> &
    Partial<Pick<OrderQuote, "bulky_fee" | "assembly_fee">>;
}) {
  const parts = (
    [
      ["includes bulky item delivery", quote.bulky_fee ?? 0],
      ["includes assembly", quote.assembly_fee ?? 0],
    ] as const
  ).filter(([, value]) => value > 0);
  return (
    <dl className="space-y-2 py-4">
      {(
        [
          ["Subtotal", quote.subtotal],
          ["Tax", quote.tax],
          ["Delivery", quote.delivery_fee],
          ["Total", quote.total],
        ] as const
      ).map(([label, value]) => (
        <div key={label}>
          <div className="flex justify-between gap-6">
            <dt>{label}</dt>
            <dd className={label === "Total" ? "font-bold" : ""}>
              {formatPrice(value)}
            </dd>
          </div>
          {label === "Delivery" &&
            parts.map(([text, amount]) => (
              <div
                key={text}
                className="flex justify-between gap-6 text-sm muted"
              >
                <dt className="pl-3">{text}</dt>
                <dd>{formatPrice(amount)}</dd>
              </div>
            ))}
        </div>
      ))}
    </dl>
  );
}
