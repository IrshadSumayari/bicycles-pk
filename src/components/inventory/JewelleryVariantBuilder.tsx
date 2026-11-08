import { jewelleryFinishes, jewellerySizes } from "../../../shared/jewellery";
export function JewelleryVariantBuilder({
  category,
  onSizes,
  onFinishes,
}: {
  category: string;
  onSizes: (sizes: string[]) => void;
  onFinishes: (values: string[]) => void;
}) {
  return (
    <div className="rounded-xl border border-border bg-card p-4 space-y-4">
      <h3 className="font-semibold text-link">Jewellery options</h3>
      <p className="text-sm text-bodytext">
        Use your supplier’s size and material labels. Finishes describe
        appearance; they do not establish metal content or purity. Enter other
        sizes or designs below.
      </p>
      <div>
        <p className="text-sm font-medium mb-2">Size / length shortcuts</p>
        <div className="flex flex-wrap gap-2">
          {jewellerySizes(category).map((size) => (
            <button
              type="button"
              className="btn btn-secondary btn-sm"
              key={size}
              onClick={() => onSizes([size])}
            >
              Add {size}
            </button>
          ))}
        </div>
      </div>
      <div>
        <p className="text-sm font-medium mb-2">Finish shortcuts</p>
        <div className="flex flex-wrap gap-2">
          {jewelleryFinishes.map((finish) => (
            <button
              type="button"
              className="btn btn-secondary btn-sm"
              key={finish}
              onClick={() => onFinishes([finish])}
            >
              Add {finish}
            </button>
          ))}
        </div>
      </div>
      <p className="text-sm text-bodytext">
        Track one sellable item per stock unit. A pair of earrings or a complete
        set counts as one item when sold together.
      </p>
    </div>
  );
}
