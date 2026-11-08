import { bagColours, bagSizes } from "../../../shared/bags";
export function BagVariantBuilder({
  category,
  onSizes,
  onColours,
}: {
  category: string;
  onSizes: (sizes: string[]) => void;
  onColours: (values: string[]) => void;
}) {
  return (
    <div className="rounded-xl border border-border bg-card p-4 space-y-4">
      <h3 className="font-semibold text-link">Bag options</h3>
      <p className="text-sm text-bodytext">
        Use a size only when the same design comes in more than one size;
        otherwise choose One size. Add the measured width, height, depth and
        strap drop in the Website tab so shoppers can see what fits.
      </p>
      <div>
        <p className="text-sm font-medium mb-2">Size shortcuts</p>
        <div className="flex flex-wrap gap-2">
          {bagSizes(category).map((size) => (
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
        <p className="text-sm font-medium mb-2">Colour shortcuts</p>
        <div className="flex flex-wrap gap-2">
          {bagColours.map((colour) => (
            <button
              type="button"
              className="btn btn-secondary btn-sm"
              key={colour}
              onClick={() => onColours([colour])}
            >
              Add {colour}
            </button>
          ))}
        </div>
      </div>
      <p className="text-sm text-bodytext">
        Track one bag per stock unit. A detachable pouch or strap that comes with
        the bag is part of the same item; list it in the Website tab.
      </p>
    </div>
  );
}
