import { notFound } from "next/navigation";
import { customerClient } from "@/lib/supabase-server";
import type { WebOrder } from "@/lib/orders";
import { CustomerOrder } from "@/components/customer-order";
import { StaffNotice } from "@/components/staff-notice";
export default async function Page({
  params,
}: {
  params: Promise<{ orderNo: string }>;
}) {
  const { orderNo } = await params;
  const { client, isCustomer } = await customerClient();
  if (!isCustomer)
    return <StaffNotice />;
  const { data, error } = await client.rpc("my_online_order", {
    p_order_no: orderNo,
  });
  if (error || !data) notFound();
  return <CustomerOrder initial={data as unknown as WebOrder} />;
}
