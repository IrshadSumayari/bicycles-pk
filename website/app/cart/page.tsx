import { CartContents } from "@/components/cart";
import { ShopHeading, CheckoutSteps } from "@/components/shop-heading";
export const metadata = {
  title: "Your shopping bag",
  robots: { index: false, follow: false },
};
export default function Page() {
  return (
    <>
      <ShopHeading
        title="Your lovely little finds."
        eyebrow="THE SHOPPING BAG"
        description="A little closer to your new favourites."
      />
      <section className="cart-page">
        <CheckoutSteps current="bag" />
        <CartContents />
      </section>
    </>
  );
}
