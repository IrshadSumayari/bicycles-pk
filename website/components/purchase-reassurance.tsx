import Link from "next/link";
import { Truck, ShieldCheck, Phone } from "lucide-react";
export function PurchaseReassurance({
  policy,
}: {
  policy?: { cod_enabled?: boolean };
}) {
  return (
    <div className="product-trust lv-purchase-reassurance">
      <p>
        <Truck size={18} />
        <span>
          Delivery across Pakistan, subject to courier coverage.{" "}
          <Link href="/policies/shipping-policy">
            Charges confirmed at checkout
          </Link>
          .
        </span>
      </p>
      <p>
        <ShieldCheck size={18} />
        <span>
          {policy?.cod_enabled
            ? "Cash on delivery for eligible orders. Checkout confirms availability."
            : "Available payment options are confirmed at checkout."}
        </span>
      </p>
      <p>
        <ShieldCheck size={18} />
        <span>
          Every return or exchange request is reviewed by staff.{" "}
          <Link href="/policies/refund-policy">Read how reviews work</Link>.
        </span>
      </p>
      <p>
        <Phone size={18} />
        <span>
          Need help before ordering?{" "}
          <Link href="/pages/contact">Contact Bicycles.pk</Link>.
        </span>
      </p>
    </div>
  );
}
