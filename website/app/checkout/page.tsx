import { customerClient } from "@/lib/supabase-server";
import { Checkout } from "@/components/checkout";
import { StaffNotice } from "@/components/staff-notice";
export const metadata = {
  title: "Checkout",
  robots: { index: false, follow: false },
};
export default async function Page() {
  const { client, user, isCustomer } = await customerClient();
  if (!isCustomer)
    return <StaffNotice className="section" />;
  const { data, error } = await client
    .from("customer_accounts")
    .select("full_name,phone,email")
    .eq("id", user.id)
    .single();
  if (error) throw error;
  return (
    <Checkout
      key={user.id}
      accountId={user.id}
      name={data.full_name ?? ""}
      phone={data.phone ?? ""}
      email={data.email ?? ""}
    />
  );
}
