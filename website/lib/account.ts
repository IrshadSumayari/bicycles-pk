export function returnPath(path: string | undefined) {
  return path &&
    (path.startsWith("/account") || path === '/checkout' || path.startsWith('/checkout/')) &&
    !path.startsWith("//") &&
    !/[\\\r\n]/.test(path)
    ? path
    : "/account";
}
export function normalizePhone(phone: string) {
  const d = phone.replace(/\D/g, "");
  if (!d) return "";
  if (d.startsWith("00")) return "+" + d.slice(2);
  if (d.length === 11 && d.startsWith("0")) return "+92" + d.slice(1);
  if (d.length === 12 && d.startsWith("92")) return "+" + d;
  if (d.length === 10 && d.startsWith("3")) return "+92" + d;
  return phone.trim().startsWith("+") ? "+" + d : d;
}
