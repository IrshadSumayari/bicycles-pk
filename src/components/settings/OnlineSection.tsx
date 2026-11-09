import { Input } from "@/components/ui/input";
import type { SettingsSectionProps } from "./sectionTypes";
export function OnlineSection({
  value,
  onChange,
  admin,
}: SettingsSectionProps) {
  if (!admin) return null;
  return (
    <section className="card p-5 space-y-4" aria-label="Online order settings">
      <h2 className="font-bold text-xl">Online orders</h2>
      <p className="text-sm text-bodytext">
        Limits apply to each website account and prevent unpaid orders from
        holding too much stock.
      </p>
      <h3 className="font-semibold">Delivery and cash on delivery</h3>
      <p className="text-sm text-bodytext">
        Delivery uses one flat fee. Free delivery is based on the item subtotal;
        the COD limit includes tax and delivery. These settings apply to website
        quotes after saving.
      </p>
      <label className="flex items-start gap-3">
        <input
          type="checkbox"
          checked={value.codEnabled ?? false}
          onChange={(event) => onChange({ codEnabled: event.target.checked })}
        />
        <span>Allow cash on delivery</span>
      </label>
      <div className="grid md:grid-cols-2 gap-4">
        <label className="block text-sm space-y-1">
          Delivery fee (PKR)
          <Input
            className="input block"
            type="number"
            min={0}
            step="0.01"
            value={value.deliveryFee ?? 0}
            onChange={(event) =>
              onChange({ deliveryFee: Number(event.target.value) })
            }
          />
          <span className="block text-bodytext">
            Pickup has no delivery fee. Zero means free delivery.
          </span>
        </label>
        <label className="block text-sm space-y-1">
          Free delivery from subtotal (PKR)
          <Input
            className="input block"
            type="number"
            min={0}
            step="0.01"
            value={value.freeDeliveryOver ?? ""}
            onChange={(event) =>
              onChange({
                freeDeliveryOver:
                  event.target.value === "" ? null : Number(event.target.value),
              })
            }
          />
          <span className="block text-bodytext">
            Leave blank to charge the delivery fee at every subtotal.
          </span>
        </label>
        <label className="block text-sm space-y-1">
          Bulky item charge per bike (PKR)
          <Input
            className="input block"
            type="number"
            min={0}
            step="0.01"
            value={value.bulkyDeliveryFee ?? 0}
            onChange={(event) =>
              onChange({ bulkyDeliveryFee: Number(event.target.value) })
            }
          />
          <span className="block text-bodytext">
            Added to courier delivery for each item marked bulky, even when
            delivery is otherwise free.
          </span>
        </label>
        <label className="block text-sm space-y-1">
          Assembly per bike (PKR)
          <Input
            className="input block"
            type="number"
            min={0}
            step="0.01"
            value={value.assemblyFee ?? ""}
            onChange={(event) =>
              onChange({
                assemblyFee:
                  event.target.value === "" ? null : Number(event.target.value),
              })
            }
          />
          <span className="block text-bodytext">
            Optional at checkout for courier orders with bulky items. Leave
            blank to not offer assembly; zero offers it free.
          </span>
        </label>
        <label className="block text-sm space-y-1">
          Maximum COD order total (PKR)
          <Input
            className="input block"
            type="number"
            min={0}
            step="0.01"
            value={value.codMaxTotal ?? ""}
            onChange={(event) =>
              onChange({
                codMaxTotal:
                  event.target.value === "" ? null : Number(event.target.value),
              })
            }
          />
          <span className="block text-bodytext">
            Leave blank for no amount limit. COD must also be enabled.
          </span>
        </label>
      </div>
      <h3 className="font-semibold">Online payment methods</h3>
      <label className="flex items-start gap-3">
        <input
          type="checkbox"
          checked={value.onlineCardEnabled ?? false}
          onChange={(event) =>
            onChange({ onlineCardEnabled: event.target.checked })
          }
        />
        <span>
          Card and Easypaisa wallet payments
          <span className="block text-sm text-bodytext">
            Turn on only after Easypaisa is connected
          </span>
        </span>
      </label>
      <div className="grid md:grid-cols-2 gap-4">
        {(
          [
            [
              "onlineMaxPendingOrders",
              "Maximum pending-payment orders",
              "How many unpaid online payment orders one customer can keep open.",
            ],
            [
              "onlineMaxOpenCodOrders",
              "Maximum open COD orders",
              "How many unfulfilled cash-on-delivery orders one customer can keep open.",
            ],
          ] as const
        ).map(([key, label, help]) => (
          <label key={key} className="block text-sm space-y-1">
            {label}
            <Input
              className="input block"
              type="number"
              min={1}
              max={50}
              step={1}
              value={value[key] ?? 3}
              onChange={(event) =>
                onChange({ [key]: Number(event.target.value) })
              }
            />
            <span className="block text-bodytext">
              {help} Choose a whole number from 1 to 50.
            </span>
          </label>
        ))}
      </div>
    </section>
  );
}
