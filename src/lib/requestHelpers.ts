import { roundMoney } from "./pricing";
export const REQUEST_LABELS: Record<string, string> = {
  submitted: "Submitted",
  reviewing: "Reviewing",
  quoted: "Quoted",
  accepted: "Accepted",
  declined: "Declined",
  cancelled: "Cancelled",
  converted: "Converted",
};
export function requestQuoteTotal(charges: { amount: string | number }[]) {
  return roundMoney(
    charges.reduce((sum, charge) => sum + (Number(charge.amount) || 0), 0),
  );
}
export function requestDate(now = new Date()) {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Karachi",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(now);
}
export function requestQuoteLink(
  phone: string | null,
  requestNo: string,
  store: string,
) {
  const digits = phone?.replace(/\D/g, "");
  return digits && digits.length >= 10
    ? `https://wa.me/${digits}?text=${encodeURIComponent(`Assalam o Alaikum, your quote for ${requestNo} at ${store} is ready. Please sign in to your website account and open My requests to review it.`)}`
    : null;
}
