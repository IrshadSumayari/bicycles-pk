import { OrderReturn } from "@/components/order-return";
export const metadata = { robots: { index: false, follow: false } };
export default function Page({
  searchParams,
}: {
  searchParams: Promise<{ order?: string; orderNo?: string }>;
}) {
  return <OrderReturn searchParams={searchParams} mode="cancel" />;
}
