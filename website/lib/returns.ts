import { browserClient } from "./supabase-browser";
import {
  prepareEvidenceImage,
  type ReturnRequest,
  type ReturnSubmission,
} from "../../shared/returns";
export const customerReturns = {
  async get(orderNo: string): Promise<ReturnRequest | null> {
    const { data, error } = await browserClient().rpc("my_return_request", {
      p_order_no: orderNo,
    });
    if (error) throw error;
    return data as unknown as ReturnRequest | null;
  },
  async create(p: ReturnSubmission): Promise<ReturnRequest> {
    const { data, error } = await browserClient().rpc("create_return_request", {
      p,
    });
    if (error) throw error;
    return data as unknown as ReturnRequest;
  },
  async reply(p: {
    id: string;
    version: number;
    message: string;
    request_id: string;
  }): Promise<ReturnRequest> {
    const { data, error } = await browserClient().rpc("reply_return_request", {
      p,
    });
    if (error) throw error;
    return data as unknown as ReturnRequest;
  },
  async upload(id: string, file: File, photoId = crypto.randomUUID()) {
    const blob = await prepareEvidenceImage(file);
    const client = browserClient();
    const { data, error } = await client.rpc("prepare_return_photo", {
      p_id: id,
      p_photo_id: photoId,
    });
    if (error) throw error;
    const photo = data as { storage_path: string; uploaded?: boolean };
    if (photo.uploaded) return;
    const result = await client.storage
      .from("return-evidence")
      .upload(photo.storage_path, blob, {
        contentType: "image/webp",
        upsert: false,
      });
    if (result.error) throw result.error;
  },
  async photo(path: string) {
    const { data, error } = await browserClient()
      .storage.from("return-evidence")
      .createSignedUrl(path, 60);
    if (error) throw error;
    return data.signedUrl;
  },
};
