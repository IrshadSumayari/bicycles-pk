import { roundMoney } from "./pricing";

// Refund for returning `qty` more of a sale line, matching the server's
// allocation: earlier returns plus this one never exceed what was paid.
export function lineRefund(
  lineTotal: number,
  lineQuantity: number,
  alreadyReturned: number,
  qty: number,
): number {
  if (lineQuantity <= 0 || qty <= 0) return 0;
  return roundMoney(
    roundMoney((lineTotal * (alreadyReturned + qty)) / lineQuantity) -
      roundMoney((lineTotal * alreadyReturned) / lineQuantity),
  );
}

export type ReturnCondition = "resaleable" | "damaged" | "faulty";
export function returnSelectionErrors(
  lines: {
    description: string;
    quantity: number;
    returned: number;
    unit: string;
    qty: string;
    condition: string;
  }[],
): string[] {
  return lines.flatMap((line) => {
    if (!line.qty.trim() || Number(line.qty) === 0) return [];
    const qty = Number(line.qty);
    if (!Number.isFinite(qty) || qty < 0)
      return [`Enter a valid return quantity for ${line.description}`];
    const errors: string[] = [];
    if (qty > line.quantity - line.returned)
      errors.push(
        `Only ${line.quantity - line.returned} of ${line.description} can be returned`,
      );
    if (!Number.isInteger(qty))
      errors.push(`Whole quantities only for ${line.description}`);
    if (!["resaleable", "damaged", "faulty"].includes(line.condition))
      errors.push(`Inspect ${line.description} and choose its condition`);
    return errors;
  });
}

export function exchangeReadiness(
  items: { description: string; qty: string; unit: string }[],
  quote: { available: boolean; fetching: boolean; error: boolean },
): string[] {
  const errors: string[] = [];
  if (!items.length) errors.push("Add the replacement items");
  for (const item of items) {
    const qty = Number(item.qty);
    if (
      !item.qty.trim() ||
      !Number.isFinite(qty) ||
      qty <= 0 ||
      !Number.isInteger(qty)
    )
      errors.push(`Enter a valid replacement quantity for ${item.description}`);
  }
  if (items.length && (!quote.available || quote.fetching || quote.error))
    errors.push(
      "Wait for a successful replacement price check before completing the exchange",
    );
  return errors;
}
