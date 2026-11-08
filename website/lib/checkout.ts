import { normalizePhone } from "./account";
export type CheckoutForm = {
  contact_name: string;
  phone: string;
  email: string;
  fulfilment: "pickup" | "delivery";
  address: { line1: string; line2: string; city: string; postal_code: string };
  payment_method: "card" | "easypaisa" | "cod";
  notes_customer: string;
};
export function validateCheckout(
  form: CheckoutForm,
  codAllowed: boolean,
  methods: readonly string[] = [],
): string | null {
  if (!form.contact_name.trim() || form.contact_name.trim().length > 200)
    return "Enter your contact name";
  if (!/^\+?[0-9]{10,15}$/.test(normalizePhone(form.phone)))
    return "Enter a valid phone number";
  if (
    form.email &&
    (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(form.email) || form.email.length > 254)
  )
    return "Enter a valid email address";
  if (
    form.fulfilment === "delivery" &&
    (!form.address.line1.trim() ||
      !form.address.city.trim() ||
      form.address.line1.length > 300 ||
      form.address.city.length > 100 ||
      form.address.line2.length > 300 ||
      form.address.postal_code.length > 20)
  )
    return "Enter the delivery address and city";
  if (form.payment_method === "cod" && !codAllowed)
    return "Cash on delivery is unavailable for this order";
  if (!["card", "easypaisa", "cod"].includes(form.payment_method))
    return "Choose a payment method";
  if (!methods.includes(form.payment_method))
    return "Choose an available payment method";
  if (form.notes_customer.length > 2000)
    return "Keep order notes under 2001 characters";
  return null;
}
export function countdown(expiresAt: string | null, now: number): string {
  if (!expiresAt) return "No payment hold";
  const seconds = Math.max(0, Math.ceil((Date.parse(expiresAt) - now) / 1000));
  if (!Number.isFinite(seconds) || seconds === 0) return "Expired";
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`;
}
export const CITIES = [
  "Karachi",
  "Lahore",
  "Islamabad",
  "Rawalpindi",
  "Faisalabad",
  "Multan",
  "Peshawar",
  "Quetta",
  "Sialkot",
  "Gujranwala",
  "Hyderabad",
];

export function paymentOptions(
  quote?: { payment_methods?: readonly string[] } | null,
) {
  const labels = {
    card: "Credit / debit card",
    easypaisa: "Easypaisa wallet",
    cod: "Cash on delivery",
  };
  return (["card", "easypaisa", "cod"] as const)
    .filter((method) => quote?.payment_methods?.includes(method))
    .map((method) => [method, labels[method]] as const);
}
