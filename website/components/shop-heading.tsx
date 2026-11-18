import Link from "next/link";
export function ShopHeading({
  title,
  eyebrow = "THE BICYCLES.PK COLLECTION",
  description,
  children,
}: {
  title: string;
  eyebrow?: string;
  description?: string;
  children?: React.ReactNode;
}) {
  return (
    <header className="lv-shop-heading">
      <nav aria-label="Breadcrumb">
        <Link href="/">Home</Link>
        <span aria-hidden="true">/</span>
        <span>{title}</span>
      </nav>
      <p className="lv-eyebrow">{eyebrow}</p>
      <h1>{title}</h1>
      {description && <p className="lv-shop-description">{description}</p>}
      {children}
    </header>
  );
}
export function CheckoutSteps({ current }: { current: "bag" | "checkout" }) {
  return (
    <ol className="lv-checkout-steps" aria-label="Shopping progress">
      <li aria-current={current === "bag" ? "step" : undefined}>
        <Link href="/cart">
          <span>01</span> Your bag
        </Link>
      </li>
      <li aria-current={current === "checkout" ? "step" : undefined}>
        <span>02</span> Checkout
      </li>
      <li>
        <span>03</span> Confirmation
      </li>
    </ol>
  );
}
