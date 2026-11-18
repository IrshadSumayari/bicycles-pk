import Link from "next/link";
import { customerClient } from "@/lib/supabase-server";
import type { WebOrder } from "@/lib/orders";
import { CustomerOrder } from "./customer-order";
import { StaffNotice } from "./staff-notice";
export async function OrderReturn({
  searchParams,
  mode,
}: {
  searchParams: Promise<{ order?: string; orderNo?: string }>;
  mode: "return" | "cancel";
}) {
  const { order, orderNo } = await searchParams;
  const no = order ?? orderNo;
  const { client, isCustomer } = await customerClient();
  if (!isCustomer)
    return <StaffNotice />;
  if (!no || !/^WEB-\d{6,}$/.test(no))
    return (
      <p className="section">
        Choose an order from <Link href="/account/orders">My orders</Link>.
      </p>
    );
  const { data, error } = await client.rpc("my_online_order", {
    p_order_no: no,
  });
  if (error)
    return (
      <p className="section">
        Order not found. <Link href="/account/orders">View your orders</Link>.
      </p>
    );
  return (
    <section className="section max-w-3xl mx-auto">
      <CustomerOrder initial={data as unknown as WebOrder} mode={mode} />
    </section>
  );
}
