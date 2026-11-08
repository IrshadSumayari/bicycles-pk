import { supabase } from "./supabase";
import type { ShipmentUpdateKind } from "../../shared/orderTracking";
export type TrackingUpdate = {
  id: string;
  version: number;
  courier: string;
  tracking_no: string;
  kind: ShipmentUpdateKind;
  message: string;
  request_id: string;
};
export async function updateOrderTracking(p: TrackingUpdate) {
  const { data, error } = await supabase.rpc("update_online_tracking", { p });
  if (error) throw error;
  return data;
}
