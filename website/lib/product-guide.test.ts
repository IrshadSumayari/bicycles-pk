import { describe, it, expect } from "vitest";
import { productGuideError, readProductGuide } from "../../shared/productGuide";
const chart = {
  unit: "cm",
  basis: "body",
  source: "Supplier A / chart 1",
  rows: [{ size: "34DD", underbust: "73–77", bust: "Not supplied" }],
};
describe("supplier product guidance", () => {
  it("keeps supplier ranges and size labels without conversion", () => {
    expect(
      productGuideError({ size_chart: chart, care: "Follow label" }),
    ).toBeNull();
    expect(
      readProductGuide({ size_chart: chart }).size_chart?.rows[0].size,
    ).toBe("34DD");
    expect(
      readProductGuide({
        size_chart: { ...chart, unit: "in", basis: "garment" },
      }).size_chart?.unit,
    ).toBe("in");
  });
  it("rejects missing units, source, basis and ambiguous or empty rows", () => {
    for (const c of [
      { ...chart, unit: "" },
      { ...chart, basis: "" },
      { ...chart, source: " " },
      { ...chart, rows: [] },
      { ...chart, rows: [{ size: "S" }] },
      { ...chart, rows: [{ size: "S", bust: 90 }] },
      {
        ...chart,
        rows: [
          { size: "S", bust: "90" },
          { size: " s ", bust: "92" },
        ],
      },
    ])
      expect(productGuideError({ size_chart: c })).not.toBeNull();
  });
  it("allows unknown metadata but rejects private and unbounded fields", () => {
    expect(readProductGuide({})).toEqual({});
    expect(productGuideError({ care: "x".repeat(2001) })).not.toBeNull();
    expect(readProductGuide({ cost: 50 })).toEqual({});
    expect(
      productGuideError({
        size_chart: {
          ...chart,
          rows: [{ size: "S", bust: "90", cost: "secret" }],
        },
      }),
    ).not.toBeNull();
  });
});

import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { SupplierSizeChart } from "../components/size-chart";
import { MeasurementIllustration } from "../components/measurement-illustration";
it("renders supplier units, unknown cells and escaped chart source accessibly", () => {
  const html = renderToStaticMarkup(
    createElement(SupplierSizeChart, {
      chart: {
        unit: "in",
        basis: "garment",
        source: "<supplier>",
        rows: [
          { size: "S", bust: "34–36" },
          { size: "M", waist: "30" },
        ],
      },
    }),
  );
  expect(html).toContain("Garment");
  expect(html).toContain("Inches (in)");
  expect(html).toContain("Not supplied");
  expect(html).toContain("&lt;supplier&gt;");
  expect(html).toContain('scope="row"');
  expect(html).toContain('tabindex="0"');
});
it("renders each measuring illustration with a single title string", () => {
  for (const kind of ["underbust", "bust", "waist", "hips"] as const) {
    const drawing = MeasurementIllustration({ kind });
    expect(typeof drawing.props.children[0].props.children).toBe("string");
    const html = renderToStaticMarkup(
      createElement(MeasurementIllustration, { kind }),
    );
    expect(html).toContain('role="img"');
    expect(html).not.toContain("<!--");
  }
});
