import { customerClient } from "@/lib/supabase-server";
import { Profile } from "@/components/profile";
import { StaffNotice } from "@/components/staff-notice";
export default async function Page() {
  const { client, user, isCustomer } = await customerClient();
  if (!isCustomer)
    return <StaffNotice />;
  const { data, error } = await client
    .from("customer_accounts")
    .select("full_name,phone,marketing_consent,email_marketing_consent,sms_marketing_consent")
    .eq("id", user.id)
    .single();
  if (error) throw error;
  return <Profile id={user.id} initial={data} />;
}
