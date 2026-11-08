export const CART_KEY = "ladyvogue-bag-v3";
export const CART_VERSION = 3;
export type CartLine = { variant_id: string; quantity: number };
export const lineKey = (line: Pick<CartLine, "variant_id">) => line.variant_id;
export type CartAction =
  | ({ type: "add" | "set" } & CartLine)
  | { type: "remove"; variant_id: string }
  | { type: "clear" }
  | { type: "load"; lines: CartLine[] };
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export function cartReducer(lines: CartLine[], action: CartAction): CartLine[] {
  if (action.type === "clear") return [];
  if (action.type === "load")
    return action.lines.reduce(
      (bag, line) => cartReducer(bag, { type: "add", ...line }),
      [] as CartLine[],
    );
  const key = lineKey(action);
  if (action.type === "remove") return lines.filter((l) => lineKey(l) !== key);
  if (
    !uuid.test(action.variant_id) ||
    !Number.isInteger(action.quantity) ||
    action.quantity < 1
  )
    return lines;
  const previous = lines.find((l) => lineKey(l) === key);
  const quantity = Math.min(
    10,
    action.quantity + (action.type === "add" ? (previous?.quantity ?? 0) : 0),
  );
  const next: CartLine = { variant_id: action.variant_id, quantity };
  if (previous) return lines.map((l) => (lineKey(l) === key ? next : l));
  return lines.length < 50 ? [...lines, next] : lines;
}
export function readCart(raw: string | null): CartLine[] {
  try {
    const data: unknown = JSON.parse(raw ?? "null");
    if (
      !data ||
      typeof data !== "object" ||
      !("version" in data) ||
      data.version !== CART_VERSION ||
      !("lines" in data) ||
      !Array.isArray(data.lines)
    )
      return [];
    return data.lines.reduce((bag: CartLine[], line: unknown) => {
      if (
        !line ||
        typeof line !== "object" ||
        !("variant_id" in line) ||
        typeof line.variant_id !== "string" ||
        !("quantity" in line) ||
        typeof line.quantity !== "number"
      )
        return bag;
      return cartReducer(bag, {
        type: "add",
        variant_id: line.variant_id,
        quantity: line.quantity,
      });
    }, []);
  } catch {
    return [];
  }
}
