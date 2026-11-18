import { customerClient } from "@/lib/supabase-server";
import { StaffNotice } from "@/components/staff-notice";
import { TrackOrderLookup } from "@/components/track-order-lookup";
export const metadata = { title: "Track my order" };
export default async function Page() {
  const { isCustomer } = await customerClient();
  if (!isCustomer) return <StaffNotice />;
  return <TrackOrderLookup />;
}
