import {
  measurementKeys,
  measurementLabels,
  productGuideError,
  type SupplierChart,
} from "../../shared/productGuide";
export function SupplierSizeChart({ chart }: { chart: SupplierChart }) {
  if (productGuideError({ size_chart: chart }))
    return (
      <p>
        The supplier chart is unavailable. Please contact us before choosing a
        size.
      </p>
    );
  const keys = measurementKeys.filter((k) =>
    chart.rows.some((r) => r[k]?.trim()),
  );
  return (
    <section className="lv-supplier-chart">
      <p>
        <strong>
          {chart.basis === "body" ? "Body" : "Garment"} measurements ·{" "}
          {chart.unit === "cm" ? "Centimetres (cm)" : "Inches (in)"}
        </strong>
        <br />
        Supplier chart: {chart.source}
      </p>
      <p>
        {chart.basis === "body"
          ? "Compare your body measurements with the ranges below."
          : "These are garment measurements. Compare with a similar garment; they are not body measurements."}{" "}
        Size labels and cup systems vary by supplier. No conversion is applied.
      </p>
      <div
        className="lv-chart-scroll"
        role="region"
        aria-label="Supplier size measurements"
        tabIndex={0}
      >
        <table>
          <caption>Measurements by size ({chart.unit})</caption>
          <thead>
            <tr>
              <th scope="col">Size</th>
              {keys.map((k) => (
                <th key={k} scope="col">
                  {measurementLabels[k]} ({chart.unit})
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {chart.rows.map((r) => (
              <tr key={r.size}>
                <th scope="row">{r.size}</th>
                {keys.map((k) => (
                  <td key={k}>{r[k]?.trim() || "Not supplied"}</td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <p className="muted text-sm">
        A chart helps you compare sizes; it cannot guarantee fit. Measurements
        not supplied by the seller are shown as unknown.
      </p>
    </section>
  );
}
