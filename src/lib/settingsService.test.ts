import { beforeEach, describe, expect, it, vi } from "vitest";
const db = vi.hoisted(() => ({ rpc: vi.fn(), from: vi.fn() }));
vi.mock("./supabase", () => ({ supabase: db }));
import { settingsService } from "./services";
const row = {
  delivery_fee: 300,
  free_delivery_over: null,
  cod_enabled: true,
  cod_max_total: 5000,
};
beforeEach(() => vi.clearAllMocks());
describe("delivery settings persistence", () => {
  it("loads the stored fee, enabled COD and nullable thresholds", async () => {
    const chain = {
      select: vi.fn(),
      order: vi.fn(),
      limit: vi.fn(),
      single: vi.fn().mockResolvedValue({ data: row, error: null }),
    };
    chain.select.mockReturnValue(chain);
    chain.order.mockReturnValue(chain);
    chain.limit.mockReturnValue(chain);
    db.from.mockReturnValue(chain);
    expect(await settingsService.get()).toMatchObject({
      deliveryFee: 300,
      freeDeliveryOver: null,
      codEnabled: true,
      codMaxTotal: 5000,
    });
  });
  it("sends only changed delivery fields, preserving zero, false and explicit clearing", async () => {
    db.rpc.mockResolvedValue({
      data: {
        ...row,
        delivery_fee: 0,
        cod_enabled: false,
        cod_max_total: null,
      },
      error: null,
    });
    const result = await settingsService.update(
      { deliveryFee: 0, codEnabled: false, codMaxTotal: null },
      "test-request",
    );
    expect(db.rpc).toHaveBeenCalledWith("update_settings", {
      p: {
        request_id: "test-request",
        delivery_fee: 0,
        cod_enabled: false,
        cod_max_total: null,
      },
    });
    expect(result).toMatchObject({
      deliveryFee: 0,
      codEnabled: false,
      codMaxTotal: null,
    });
  });
});
