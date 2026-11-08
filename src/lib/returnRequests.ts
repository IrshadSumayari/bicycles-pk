import { supabase } from "./supabase";
import type { ReturnRequest, ReturnStatus } from "../../shared/returns";
export type ReturnReview = {
  id: string;
  version: number;
  status: ReturnStatus;
  message: string;
  staff_note: string;
  request_id: string;
};
export const returnRequests = {
  async list(status: string, offset: number) {
    const { data, error } = await supabase.rpc("list_return_requests", {
      p: { status, offset, limit: 24 },
    });
    if (error) throw error;
    return data as unknown as {
      requests: {
        id: string;
        order_id: string;
        order_no: string;
        status: ReturnStatus;
        updated_at: string;
      }[];
      total_count: number;
    };
  },
  async detail(orderId: string) {
    const { data, error } = await supabase.rpc("staff_return_request", {
      p_order_id: orderId,
    });
    if (error) throw error;
    return data as unknown as ReturnRequest | null;
  },
  async review(p: ReturnReview) {
    const { error } = await supabase.rpc("review_return_request", { p });
    if (error) throw error;
  },
  async photo(path: string) {
    const { data, error } = await supabase.storage
      .from("return-evidence")
      .createSignedUrl(path, 60);
    if (error) throw error;
    return data.signedUrl;
  },
};
