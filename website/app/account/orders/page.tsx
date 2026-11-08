import { customerClient } from "@/lib/supabase-server";
import { type WebOrder } from "@/lib/orders";
import { CustomerOrders } from "@/components/customer-orders";
import { StaffNotice } from "@/components/staff-notice";
export default async function Page() {
  const { client, isCustomer } = await customerClient();
  if (!isCustomer) return <StaffNotice />;
  const { data, error } = await client.rpc("my_online_orders");
  if (error) throw error;
  const orders = data as unknown as WebOrder[];
  return <CustomerOrders orders={orders} />;
}
