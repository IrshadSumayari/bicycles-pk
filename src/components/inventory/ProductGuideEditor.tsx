import {
  measurementKeys,
  measurementLabels,
  type ProductGuide,
  type SupplierChart,
} from "../../../shared/productGuide";
import { Input } from "../ui/input";
export function ProductGuideEditor({
  value,
  onChange,
}: {
  value: ProductGuide;
  onChange: (v: ProductGuide) => void;
}) {
  const chart = value.size_chart;
  function updateChart(patch: Partial<SupplierChart>) {
    if (chart) onChange({ ...value, size_chart: { ...chart, ...patch } });
  }
  return (
    <section
      className="rounded-xl border border-border p-4 space-y-4"
      aria-label="Fit, care and size chart"
    >
      <h3 className="font-semibold">Fit, care & size chart</h3>
      <p className="text-sm text-bodytext">
        Add supplier-confirmed information for this product only. Leave unknown
        details blank. A chart does not create stock or change existing sizes.
      </p>
      {(["included", "fit", "care"] as const).map((k) => (
        <label className="block space-y-1" key={k}>
          {
            {
              included: "Included pieces",
              fit: "Fit notes",
              care: "Care instructions",
            }[k]
          }
          <textarea
            className="textarea block w-full"
            rows={2}
            maxLength={2000}
            value={value[k] ?? ""}
            onChange={(e) => onChange({ ...value, [k]: e.target.value })}
          />
        </label>
      ))}
      <label className="flex gap-2 items-center">
        <input
          type="checkbox"
          checked={!!chart}
          onChange={(e) => {
            const next = { ...value };
            if (e.target.checked)
              next.size_chart = {
                unit: "" as SupplierChart["unit"],
                basis: "" as SupplierChart["basis"],
                source: "",
                rows: [{ size: "" }],
              };
            else delete next.size_chart;
            onChange(next);
          }}
        />
        Use a product-specific supplier chart
      </label>
      {!chart && (
        <p className="text-sm text-bodytext">
          The existing size-scheme chart remains the fallback. Enable this only
          when a confirmed product chart is available.
        </p>
      )}
      {chart && (
        <>
          <p className="text-sm text-bodytext">
            Confirm the unit and whether the chart describes body or garment
            measurements. Copy ranges exactly; no conversion is applied.
          </p>
          <div className="grid sm:grid-cols-2 gap-3">
            <label>
              Chart unit
              <select
                className="select block w-full"
                value={chart.unit}
                onChange={(e) =>
                  updateChart({ unit: e.target.value as SupplierChart["unit"] })
                }
              >
                <option value="" disabled>
                  Choose unit
                </option>
                <option value="cm">Centimetres (cm)</option>
                <option value="in">Inches (in)</option>
              </select>
            </label>
            <label>
              Measurements describe
              <select
                className="select block w-full"
                value={chart.basis}
                onChange={(e) =>
                  updateChart({
                    basis: e.target.value as SupplierChart["basis"],
                  })
                }
              >
                <option value="" disabled>
                  Choose measurement basis
                </option>
                <option value="body">Body measurements</option>
                <option value="garment">Garment measurements</option>
              </select>
            </label>
          </div>
          <label className="block">
            Supplier / chart source
            <Input
              className="input block w-full"
              maxLength={160}
              value={chart.source}
              placeholder="Supplier and chart name or reference"
              onChange={(e) => updateChart({ source: e.target.value })}
            />
          </label>
          <div
            className="overflow-x-auto"
            role="region"
            aria-label="Supplier chart editor"
            tabIndex={0}
          >
            <table className="w-full">
              <caption className="text-left text-sm">
                Supplier measurements ({chart.unit || "choose unit"}); up to 30
                sizes. Blank cells stay unknown.
              </caption>
              <thead>
                <tr>
                  {[
                    "Size",
                    ...measurementKeys.map((k) => measurementLabels[k]),
                    "Actions",
                  ].map((k) => (
                    <th key={k} scope="col" className="p-2 text-left">
                      {k}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {chart.rows.map((row, i) => (
                  <tr key={i}>
                    {(["size", ...measurementKeys] as const).map((k) => (
                      <td key={k} className="p-1">
                        <Input
                          className="input min-w-24"
                          maxLength={60}
                          aria-label={k + " for chart row " + (i + 1)}
                          value={row[k] ?? ""}
                          onChange={(e) =>
                            updateChart({
                              rows: chart.rows.map((r, j) =>
                                j === i ? { ...r, [k]: e.target.value } : r,
                              ),
                            })
                          }
                        />
                      </td>
                    ))}
                    <td>
                      <button
                        type="button"
                        className="btn btn-light"
                        onClick={() =>
                          updateChart({
                            rows: chart.rows.filter((_, j) => j !== i),
                          })
                        }
                        aria-label={"Remove chart row " + (i + 1)}
                      >
                        Remove
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <button
            type="button"
            className="btn btn-light"
            disabled={chart.rows.length >= 30}
            onClick={() => updateChart({ rows: [...chart.rows, { size: "" }] })}
          >
            Add chart row
          </button>
        </>
      )}
    </section>
  );
}
